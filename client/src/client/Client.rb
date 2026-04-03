require "gosu"
require "json"
require "logger"
require "websocket-eventmachine-client"
require_relative "../cards/CardDrawer"
require_relative "../game/GameMaster"
require_relative "../Logger"

include MyLogger

gameWindow = nil
gameMaster = nil

EM.run do

  ws = WebSocket::EventMachine::Client.connect(:uri => 'ws://localhost:25252')

  ws.onopen do
    logger.debug("Connected")
    cardDrawer = CardDrawer.new("../../resources/cards/")
    gameMaster = GameMaster.new(ws, cardDrawer)
    gosuThread = Thread.new {
      gameWindow = GameWindow.new(gameMaster)
      logger.info("Starting game window")
      gameWindow.show()
    }
    
    msgHash = { "action": "request_place" }
    ws.send(JSON.generate(msgHash))
  end

  ws.onmessage do |msgJson, type|
    msg = JSON.parse(msgJson)
    logger.debug("Received message: #{msg}")
    case msg["type"]
    when "action"
      msg = msg["msg"]
      case msg["type"]
      when "set_player_location"
        gameMaster.setFrontPlayer(msg["location"])
      when "player_connected"
        gameMaster.playerConnected(msg["location"])
      when "player_disconnected"
        gameMaster.playerDisconnected(msg["location"])
      else
        logger.warn("Received action message with unknown type #{msg["type"]}")
      end
    when "actionable"
      msg = msg["msg"]
      case msg["type"]
      when "play"
        logger.warn("Received actionable message with unhandled type #{msg["type"]}")
      when "draw"
        logger.warn("Received actionable message with unhandled type #{msg["type"]}")
      when "discard"
        logger.warn("Received actionable message with unhandled type #{msg["type"]}")
      else
        logger.warn("Received actionable message with unknown type #{msg["type"]}")
      end
    when "info"
      logger.warn("Received message unhandled type #{msg["type"]}")
    else
      logger.warn("Received message with an unknown type #{msg["type"]}")
    end
  end

  ws.onclose do |code, reason|
    logger.debug("Disconnected with status code: #{code}")
    exit
  end

end