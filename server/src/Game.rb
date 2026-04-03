require "json"
require_relative "./MessageBuilder"
require_relative "./Logger"

class Game
  include MyLogger

  @@GamesFolder = "../resources/games/"
  @@StepPrefix = "step_"

  # @param gamefile The filename for the instruction set (excluding the .json)
  def initialize(gameFile)
    @gameStarted = false
    @gameInstructions = JSON.parse((IO.read("#{@@GamesFolder}#{gameFile}")).gsub(/\r/," ").gsub(/\n/," "))
    @finalInstructionStep = 0
    @players = {}
    @playerCount = 0
    @playerScores = {}
    @hands = {}
    @startingDeck = []
    @deck = []
    @discard = []

    # Some variables to avoid having to pass around to/from helper functions
    @curStep = 1
    @repeatIncrementers = {}

    # Message queues
    # TODO mutex?
    @outgoingMsgQ = []

    initializeGame()
  end

  def runGame()
    @gameStarted = true
    gameComplete = false

    presetup(@gameInstructions) # Sets repeatIncrementers and finalInstructionStep

    while !gameComplete do
      if(@curStep <= @finalInstructionStep)
        runStep(@gameInstructions["#{@@StepPrefix}#{@curStep}"])
      else
        gameComplete = true
      end
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
        @finalInstructionStep = currentStep
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

    if(finalPlayerDir != nil)
      @playerCount += 1
      defineWebsocketResponses(websocket, finalPlayerDir)

      if(!@gameStarted && @playerCount == @players.keys.size)
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
    @startingDeck = initInstructions["deck"]["cards"]
    @deck.replace(@startingDeck)
    initInstructions["players"].each do |player|
      @players[player] = nil
      @playerScores[player] = 0
      @hands[player] = []
    end
  end
  
  def addOutgoingMessage(msg, receivingPlayers)
    @outgoingMsgQ.push([msg, receivingPlayers])
  end
  
  def defineWebsocketResponses(ws, playerDir)
    ws.onmessage do |msg, type|
      logger.info("Received message from playerDir #{playerDir}")
      logger.debug("#{playerDir} message: #{msg}")
      receivedMessage(msg, playerDir)
    end

    ws.onclose do
      @players[playerDir] = nil
      @playerCount -= 1
      indicatePlayerDisconnected(playerDir)
      logger.info("Player in seat #{playerDir} disconnected")
    end
  end
  
  def receivedMessage(msgJson, player)
    msg = JSON.parse(msgJson)
    case msg["action"]
    when "request_place"
      logger.debug("Received #{msg["action"]} message from player #{player}")
      handleRequestPlaceMsg(msg, player)
    when "draw"
      logger.warning("Received message with unhandled action type #{msg["action"]}")
    when "play"
      logger.warning("Received message with unhandled action type #{msg["action"]}")
    when "discard"
      logger.warning("Received message with unhandled action type #{msg["action"]}")
    end
  end

  def handleRequestPlaceMsg(msg, player)
    finalPlayerDir = player
    if(msg["place"] != nil)
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
    end
    outgoingMsg = {"type": "set_player_location", "location": finalPlayerDir}
    addOutgoingMessage(MessageBuilder.buildActionMessage(outgoingMsg), [finalPlayerDir])
    indicatePlayerConnected(finalPlayerDir)
    informState(finalPlayerDir)
  end
  private :handleRequestPlaceMsg

  def indicatePlayerConnected(connectedPlayerDir, playersToMsg = getConnectedPlayers())
    outgoingMsg = {"type": "player_connected", "location": connectedPlayerDir}
    addOutgoingMessage(MessageBuilder.buildActionMessage(outgoingMsg), playersToMsg)
  end

  def indicatePlayerDisconnected(disconnectedPlayerDir)
    outgoingMsg = {"type": "player_disconnected", "location": disconnectedPlayerDir}
    addOutgoingMessage(MessageBuilder.buildActionMessage(outgoingMsg), getConnectedPlayers())
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
    conPlayers = @players.select { |key, value| value != nil }
    return conPlayers.keys
  end

  def sendMessage(msg, receivingPlayers)
    logger.info("Sending message to #{receivingPlayers}")
    receivingPlayers.each do |player|
      logger.debug("Sending message to #{player}: #{msg}")
      @players[player].send(msg)
    end
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
    logger.warn("UNIMPLEMENTED ACTION TYPE")
  end

  def runStepRepeat(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
  end

  def runStepActionable(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
  end

  def runStepAssignTrick(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
  end

  def runStepScore(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
  end

  def runStepWinner(stepHash)
    logger.warn("UNIMPLEMENTED ACTION TYPE")
  end
end