require "json"
require_relative "./MessageBuilder"
require_relative "./Logger"

class Game
  include MyLogger

  @@GamesFolder = "../resources/games/"
  @@StepPrefix = "step_"

  # @param gamefile The filename for the instruction set (excluding the .json)
  def initialize(gameFile)
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
    @outgoingMsgQ = {}
    @incomingMsgQ = {}

    initializeGame()
  end

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

  def runGame()
    instructions = JSON.parse(IO.read(instructionFile))
    gameComplete = false

    presetup(instructions) # Sets repeatIncrementers and finalInstructionStep

    while !gameComplete do
      if(@curStep <= @finalInstructionStep)
        runStep(instructions["#{@@StepPrefix}#{step}"])
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

  # @param websocket The websocket connection to the player
  def addPlayer(websocket, playerDir = nil)
    if(playerDir != nil)
      logger.debug("Adding new player with requested direction: #{playerDir}")
    end

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
      msg = {"type": "set_player_location", "location": finalPlayerDir}
      sendMessage(MessageBuilder.buildActionMessage(msg), [finalPlayerDir])

      if(@playerCount == @players.keys.size)
        runGame()
      end
    end
  end

  def receivedMessage(msg)

  end

  def sendMessage(msg, receivingPlayers)
    logger.info("Sending #{msg["type"]} message to #{receivingPlayers}")
    receivingPlayers.each do |player|
      logger.debug("Sending message to #{player}: #{msg}")
      @players[player].send(msg)
    end
  end
end