require "concurrent"
require "json"
require_relative "./Card"
require_relative "./MessageBuilder"
require_relative "./Logger"

LOCATION = {
  "S" => 0,
  "W" => 1,
  "N" => 2,
  "E" => 3
}

def numToDirectionHash(num)
  dirs = LOCATION.keys
  return dirs[num % dirs.size]
end

class Game
  include MyLogger

  attr_reader :gameStarted

  @@GamesFolder = "../resources/games/"
  @@StepPrefix = "step_"

  # @param gamefile The filename for the instruction set (excluding the .json)
  def initialize(gameFile)
    @rng = Random.new()

    @gameStarted = false
    @gameInstructions = JSON.parse((IO.read("#{@@GamesFolder}#{gameFile}")).gsub(/\r/," ").gsub(/\n/," "))
    @finalInstructionStep = 0
    @playersReady = {}
    @players = {}
    @playerCount = 0
    @playerScores = {}
    @hands = {}
    @playAreas = {}
    # TODO Card scorer
    @startingDeck = []
    setStartingDeck(@gameInstructions["game"]["deck"])
    @deck = []
    @discard = []

    # Data locks
    @playersLock = Concurrent::ReadWriteLock.new
    @handsLock = Concurrent::ReadWriteLock.new

    # Visibility state
    @deckVisibility = false
    @discardVisibility = false

    # Special variables for use by the instructions during the game
    @lastWinner = nil
    @curPlayer = nil

    # Variables for waiting on and handling client actions ("actionables")
    @actionableLatch = nil
    @curActionables = {}

    # Some variables to avoid having to pass around to/from helper functions
    @curStep = 1
    @repeatIncrementers = {}

    # Message queues
    # TODO mutex?
    @outgoingMsgQ = []

    initializeGame()
  end

  def runGame()
    allPlayersReady = false
    @playersLock.with_read_lock {
      allPlayersReady = !@playersReady.has_value?(false)
    }
    if(!allPlayersReady)
      logger.debug("Not starting game until room is full")
    elsif(@gameStarted)
      logger.debug("Something tried to run the game an extra time")
    else
      logger.info("Starting game")

      @gameStarted = true

      gameComplete = false

      presetup(@gameInstructions) # Sets repeatIncrementers and finalInstructionStep
      @deckVisibility = @gameInstructions["game"]["deck"]["visible"]
      indicateDeckVisibility()
      @deck = @startingDeck
      indicateDeck()

      @discardVisibility = @gameInstructions["game"]["discard"]["visible"]
      indicateDiscardVisibility()

      while !gameComplete do
        if(@curStep <= @finalInstructionStep)
          nextStepName = "#{@@StepPrefix}#{@curStep}"
          logger.info("Running step \"#{nextStepName}\"")
          runStep(@gameInstructions["#{nextStepName}"])
          sleep(2)
        else
          logger.info("Game completed")
          gameComplete = true
        end
      end
    end
  end

  def indicateDeck()
    @deck.each do |card|
      addOutgoingMessage(MessageBuilder.buildAddCardMessage(nil, nil, "deck"))
    end
    #sleep(5)
  end

  def indicateDrawnCard(card, playerDrawing, ownHandHidden, otherHandsHidden)
    drawingHandSuit = ownHandHidden ? nil : card.suit
    drawingHandValue = ownHandHidden ? nil : card.value
    otherHandsSuit = otherHandsHidden ? nil : card.suit
    otherHandsValue = otherHandsHidden ? nil : card.value

    addOutgoingMessage(MessageBuilder.buildAddCardMessage(drawingHandSuit, drawingHandValue, "hand", playerDrawing), [playerDrawing])
    addOutgoingMessage(MessageBuilder.buildAddCardMessage(otherHandsSuit, otherHandsValue, "hand", playerDrawing), getOtherPlayers(playerDrawing))
  end

  def setStartingDeck(deckInst)
    cards = deckInst["cards"]
    cardsList = cards["all"]
    # card list with no differentiation between trump and fail cards
    if(cardsList != nil)
      cardsParsed = parseCardList(cardList)
      @startingDeck = cardsParsed["flat"]
      # TODO Give the card scorer the hierarchical list
    else # card list with some level of trump (may be determined at the start of a hand)
      allCards = []
      trumpList = cards["trump"]
      logger.debug("trumpList: #{trumpList}")
      if(trumpList != nil)
        trumpParsed = parseCardList(trumpList)
        trumpHier = trumpParsed["hier"]
        trumpFlat = trumpParsed["flat"]
        allCards.append(trumpFlat)
      end
      failList = cards["fail"]
      failParsed = parseCardList(failList)
      failHier = failParsed["hier"]
      failFlat = failParsed["flat"]
      allCards.append(failFlat)
      # TODO Give the card scorer the hierarchical lists

      logger.debug("setting starting deck to #{allCards}")
      @startingDeck = allCards.flatten()
    end
  end

  def presetup(instructionsHash)
    stepsComplete = false
    currentStep = 1
    while !stepsComplete do
      currentStepInstructions = instructionsHash["#{@@StepPrefix}#{currentStep}"]
      if(currentStepInstructions != nil)
        if(currentStepInstructions["action"] == "repeat_until" &&
           currentStepInstructions["condition"]["type"] == "occurrences")
          @repeatIncrementers[currentStep] = 0
        end
      else
        stepsComplete = true
        @finalInstructionStep = currentStep - 1
      end

      currentStep += 1
    end
  end

  # @param websocket The websocket connection to the player
  def addPlayer(websocket, playerDir = nil)
    if(playerDir != nil)
      logger.debug("Adding new player with requested direction: #{playerDir}")
    end

    # Determine player's seat
    finalPlayerDir = nil
    @playersLock.with_write_lock {
      if(playerDir != nil && @players.any?{ |player| player == playerDir })
        @players[playerDir] = websocket
        finalPlayerDir = playerDir
      elsif(playerDir == nil)
        @players.each do |key,value|
          if(value == nil)
            @players[key] = websocket
            finalPlayerDir = key
            break
          end
        end

        if(finalPlayerDir == nil)
          logger.error("New client tried to join, but there's no room!")
        end
      else
        logger.error("New client connection provided invalid player direction")
      end
      logger.info("New client set to player position: #{finalPlayerDir}")
    }

    if(finalPlayerDir != nil)
      defineWebsocketResponses(websocket, finalPlayerDir)
      @playerCount += 1

      if(!@gameStarted)
        runGame()
      end
    end
  end

  def tick()
    tempOutgoingMsgQ = @outgoingMsgQ
    @outgoingMsgQ = []
    tempOutgoingMsgQ.each do |item|
      msg = item[0]
      receivingPlayers = item[1]
      sendMessage(msg, receivingPlayers)
    end
  end


  private

  def initializeGame()
    initInstructions = @gameInstructions["game"]
    @playersLock.with_write_lock {
      @handsLock.with_write_lock {
        initInstructions["players"].each do |player|
          @playersReady[player] = false
          @players[player] = nil
          @playerScores[player] = 0
          @hands[player] = []
          @playAreas[player] = []
          @curPlayer = player
        end
      }
    }
  end
  
  def addOutgoingMessage(msg, receivingPlayers = getConnectedPlayers())
    @outgoingMsgQ.push([msg, receivingPlayers])
  end
  
  def defineWebsocketResponses(ws, playerDir)
    ws.onmessage do |msg, type|
      logger.info("Received message from playerDir #{playerDir}")
      logger.debug("#{playerDir} message: #{msg}")
      receivedMessage(msg, playerDir)
    end

    ws.onclose do
      connectedPlayers = getConnectedPlayers()
      @playersLock.with_write_lock {
        @players[playerDir] = nil
        @playersReady[playerDir] = false
        @playerCount -= 1
      }
      indicatePlayerDisconnected(playerDir)
      logger.info("Player in seat #{playerDir} disconnected")
    end
  end
  
  def receivedMessage(msgJson, player)
    msg = JSON.parse(msgJson)
    attemptedAction = msg["action"]
    if(attemptedAction == nil)
      logger.warning("Received message with no attempted action, ignoring...")
      return
    end

    # Check that a player isn't trying to play out of turn
    actionablesList = ["draw", "play", "discard"]
    if(actionablesList.include?(attemptedAction) && @curPlayer != nil && player != @curPlayer)
      logger.warning("Player in slot #{player} tried to perform #{attemptedAction} out of turn! Ignoring...")
      return
    end

    case attemptedAction
    when "request_place"
      logger.debug("Received #{msg["action"]} message from player #{player}")
      handleRequestPlaceMsg(msg, player)
    when "draw"
      logger.debug("Received #{msg["action"]} message from player #{player}")
      handleDrawMsg(msg, player)
    when "play"
      logger.debug("Received #{msg["action"]} message from player #{player}")
      handlePlayMessage(msg, player)
    when "discard"
      logger.debug("Received #{msg["action"]} message from player #{player}")
      handleDiscardMessage(msg, player)
    else
      logger.warning("Received unknown #{msg["action"]} message from player #{player}")
    end
  end

  def handleDrawMessage(msg, player)
    @curActionables["draw"] = @curActionables["draw"] - 1

    case msg["subject"]
    when "deck"
      indexToDraw = @deck.size() - 1
      drawnCard = removeCard(indexToDraw, "deck")
      addCard(drawnCard, "hand", player)
    when "discard"
      indexToDraw = @discard.size() - 1
      drawnCard = removeCard(indexToDraw, "discard")
      addCard(drawnCard, "hand", player)
    end

    if(@curActionables["draw"] == 0)
      @actionableLatch.count_down()
    end
  end

  def handlePlayMessage(msg, player)
    @curActionables["play"] = @curActionables["play"] - msg["index"].size()
    indicesToPlay = msg["index"].sort { |a,b| b <=> a }

    indicesToPlay.each do | i |
      playedCard = removeCard(i, "hand", player)
      addCard(playedCard, "play_area", player)
    end

    if(@curActionables["play"] == 0)
      @actionableLatch.count_down()
    end
  end

  def handleDiscardMessage(msg, player)
    @curActionables["discard"] = @curActionables["discard"] - msg["index"].size()
    indicesToDiscard = msg["index"].sort { |a,b| b <=> a }

    indicesToDiscard.each do | i |
      discardedCard = removeCard(i, "hand", player)
      addCard(playedCard, "discard")
    end

    if(@curActionables["discard"] == 0)
      @actionableLatch.count_down()
    end
  end

  def parseCardList(cardList)
    flatParsedCards = parseCardsFlat(cardList)
    hierarchicalParsedCards = parseCardsHierarchical(cardList)
    return { "flat" => flatParsedCards, "hier" => hierarchicalParsedCards}
  end

  def parseCardsFlat(list)
    toReturn = list.flatten.map do |cardString|
      suit, value = cardString.split('_')
      Card.new(suit, value)
    end
    return toReturn
  end

  def parseCardsHierarchical(list)
    toReturn = list.map do |element|
      if element.is_a?(Array)
        parseCardsHierarchical(element)
      else
        suit, value = element.split('_')
        Card.new(suit, value)
      end
    end
    return toReturn
  end

  def indicateDeckVisibility(playersToMsg = getConnectedPlayers())
    msg = {
      "type": "set_visibility",
      "subject": "deck",
      "visible": "#{@deckVisibility}"
    }
    addOutgoingMessage(MessageBuilder.buildInfoMessage(msg), playersToMsg)
  end

  def shuffleDeck()
    shuffledDeck = []
    while !@deck.empty? do
      shuffledDeck.append(@deck.delete_at(@rng.rand(@deck.size())))
    end
    @deck = shuffledDeck
  end

  def setStartingDiscard(discardInst)
    @discardVisibility = discardInst["visible"]
    indicateDiscardVisibility()
  end

  def indicateDiscardVisibility(playersToMsg = getConnectedPlayers())
    msg = {
      "type": "set_visibility",
      "subject": "discard",
      "visible": "#{@discardVisibility}"
    }
    addOutgoingMessage(MessageBuilder.buildInfoMessage(msg), playersToMsg)
  end

  def addCard(card, subject, dir = nil)
    case subject
    when "deck"
      @deck.append(card)
      addOutgoingMessage(MessageBuilder.buildAddCardMessage(nil, nil, "deck"))
    when "discard"
      @discard.append(card)
      addOutgoingMessage(MessageBuilder.buildAddCardMessage(card.suit, card.value, "discard"))
    when "hand"
      @handsLock.with_write_lock {
        @hands[dir].append(card)
      }
      otherPlayers = getOtherPlayers(dir)
      indicateDrawnCard(card, dir, false, true)
    when "play_area"
      @handsLock.with_write_lock {
        @playAreas[dir].append(card)
      }
      otherPlayers = getOtherPlayers(dir)
      addOutgoingMessage(MessageBuilder.buildAddCardMessage(card.suit, card.value, "play_area", dir))
    else
      logger.warn("Tried to add card to unknown subject #{subject}")
    end
  end

  def removeCard(index, subject, dir = nil)
    removedCard = nil

    case subject
    when "deck"
      removedCard = @deck.delete_at(index)
      addOutgoingMessage(MessageBuilder.buildRemoveCardMessage(index, "deck"))
    when "discard"
      removedCard = @discard.delete_at(index)
      addOutgoingMessage(MessageBuilder.buildRemoveCardMessage(index, "discard"))
    when "hand"
      @handsLock.with_write_lock {
        removedCard = @hands[dir].delete_at(index)
      }
      addOutgoingMessage(MessageBuilder.buildRemoveCardMessage(index, "hand", dir))
    when "play_area"
      @handsLock.with_write_lock {
        removedCard = @playAreas[dir].delete_at(index)
      }
      addOutgoingMessage(MessageBuilder.buildRemoveCardMessage(index, "play_area", dir))
    else
      logger.warn("Tried to remove card from unknown subject #{subject}")
    end

    return removedCard
  end

  def handleRequestPlaceMsg(msg, player)
    finalPlayerDir = player
    if(msg["place"] != nil)
      @playersLock.with_write_lock {
        requestedPlace = msg["place"]
        if(@players.any?{ |player| player == requestedPlace } && @players["place"] == nil)
          finalPlayerDir = requestedPlace
          messagingPlayerWs = @players[player]
          @players[finalPlayerDir] = messagingPlayerWs
          @players[player] = nil
          # Have to fix the responses, else we'll think they're still in their old seat when they send us messages
          defineWebsocketResponses(messagingPlayerWs, finalPlayerDir)
          logger.info("Player in slot #{player} was reassigned to slot #{finalPlayerDir}")
        end
      }
    end
    outgoingMsg = {"type": "set_player_location", "location": finalPlayerDir}
    addOutgoingMessage(MessageBuilder.buildActionMessage(outgoingMsg), [finalPlayerDir])
    indicatePlayerConnected(finalPlayerDir)
    informState(finalPlayerDir)
    @playersLock.with_write_lock {
      @playersReady[finalPlayerDir] = true
    }
  end

  def indicatePlayerConnected(connectedPlayerDir, playersToMsg = getConnectedPlayers())
    outgoingMsg = {"type": "player_connected", "location": connectedPlayerDir}
    addOutgoingMessage(MessageBuilder.buildActionMessage(outgoingMsg), playersToMsg)
  end

  def indicatePlayerDisconnected(disconnectedPlayerDir)
    outgoingMsg = {"type": "player_disconnected", "location": disconnectedPlayerDir}
    addOutgoingMessage(MessageBuilder.buildActionMessage(outgoingMsg), getConnectedPlayers())
  end

  def getOtherPlayers(dir)
    return getConnectedPlayers().filter { |player| player != dir }
  end

  def informState(playerDir)
    logger.info("Reupping state for player in slot #{playerDir}")

    connectedPlayers = getConnectedPlayers()
    logger.debug("Reupping connected players state: #{connectedPlayers}")
    connectedPlayers.each do |dir|
      indicatePlayerConnected(dir, [playerDir])
    end
    if(@gameStarted)
      #TODO Indicate game state
    end
  end

  def getConnectedPlayers()
    conPlayers = nil
    @playersLock.with_read_lock {
      conPlayers = @players.select { |key, value| value != nil }
    }
    return conPlayers.keys
  end

  def sendMessage(msg, receivingPlayers)
    logger.info("Sending message to #{receivingPlayers}")
    if(!receivingPlayers.respond_to?("each"))
      player = receivingPlayers
      logger.debug("Sending message to #{player}: #{msg}")
      @playersLock.with_read_lock {
        if(@players[player] != nil)
          @players[player].send(msg)
        else
          logger.debug("Couldn't send message to slot #{player} because they weren't connected")
        end
      }
    else
      receivingPlayers.each do |player|
        logger.debug("Sending message to #{player}: #{msg}")
        @playersLock.with_read_lock {
          if(@players[player] != nil)
            @players[player].send(msg)
          else
            logger.debug("Couldn't send message to slot #{player} because they weren't connected")
          end
        }
      end
    end
  end

  def getNextPlayer(location)
    nextPlayer = location
    viablePlayer = false
    while(!viablePlayer)
      nextPlayer = numToDirectionHash(LOCATION[location] + 1)
      if(@players.has_key(nextPlayer))
        viablePlayer = true
      end
    end

    return nextPlayer
  end

  # Step helpers
  
  # @param stepHash Instructions for the step as a hash (the highest level should always be "step_x" where x is the number of the step)
  def runStep(stepHash)
    logger.debug("Running step: #{stepHash}")
    case stepHash["action"]
    when "setup"
      runStepSetup(stepHash)
    when "actionable"
      runStepActionable(stepHash)
    when "repeat_until"
      runStepRepeat(stepHash)
    when "assign_trick"
      runStepAssignTrick(stepHash)
    when "score"
      runStepScore(stepHash)
    when "assign_winner"
      runStepWinner(stepHash)
    else
      logger.error("Game instructions had an invalid action instruction: #{stepHash["action"]}")
    end
  end

  def runStepSetup(stepHash)
    changePrefix = "change_"
    changeNum = 1
    changesRemaining = true
    while(changesRemaining)
      curChange = stepHash["#{changePrefix}#{changeNum}"]
      if(curChange == nil)
        changesRemaining = false
      else
        case curChange["action"]
        when "reset_hand"
          @hands.each do |dir, hand|
            while !hand.empty? do
              removeCard(0, "hand", dir)
            end
          end
        when "shuffle_deck"
          shuffleDeck()
        when "draw"
          numToDraw = curChange["amount"]
          if(numToDraw == nil)
            numToDraw = @deck.size() / @players.size()
          end
          while numToDraw > 0 do
            @hands.each_key do |hand|
              drawnCard = removeCard(0, "deck")
              addCard(drawnCard, "hand", hand)
            end
            numToDraw -= 1
          end
        end
      end

      changeNum += 1
    end

    @curStep += 1
  end

  def runStepRepeat(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
    @curStep += 1
  end

  def runStepActionable(stepHash)
    msg = { "actionables" => stepHash["actionables"] }

    actionPrefix = "action_"
    actionables = stepHash["actionables"]
    curActionNum = 1
    curAction = actionables["#{actionPrefix}#{curActionNum}"]
    actionsRemaining = true
    while(actionsRemaining)
      @curActionables[curAction["action"]] = curAction["count"]

      curActionNum += 1
      curAction = actionables["#{actionPrefix}#{curActionNum}"]
      actionsRemaining = curAction != nil
    end
    addOutgoingMessage(MessageBuilder.buildActionableMessage(msg), [@curPlayer])

    @actionableLatch = Concurrent::CountDownLatch.new(1)
    @actionableLatch.wait()

    @curStep += 1
  end

  def runStepAssignTrick(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
    @curStep += 1
  end

  def runStepScore(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
    @curStep += 1
  end

  def runStepWinner(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
    @curStep += 1
  end
end