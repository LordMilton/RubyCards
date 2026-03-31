require "gosu"
require "logger"
require "websocket-eventmachine-client"
require_relative "../cards/CardDrawer"
require_relative "../game/GameMaster"

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

gameWindow = nil
gameMaster = nil

EM.run do

  ws = WebSocket::EventMachine::Client.connect(:uri => 'ws://localhost:25252')

  ws.onopen do
    logger.debug("Connected")
    cardDrawer = CardDrawer.new("../../resources/cards/")
    gameMaster = GameMaster.new(cardDrawer)
    gameWindow = GameWindow.new(gameMaster).show()
  end

  ws.onmessage do |msg, type|
    logger.debug("Received message: #{msg}")
    case msg["type"]
    when "nil"
      logger.warn("Received message with no type")
    when "action"
      logger.warn("Received message unhandled type #{msg["type"]}")
    when "actionable"
      logger.warn("Received message unhandled type #{msg["type"]}")
    when "info"
      logger.warn("Received message unhandled type #{msg["type"]}")
    end
  end

  ws.onclose do |code, reason|
    logger.debug("Disconnected with status code: #{code}")
  end

  EventMachine.next_tick do
    ws.send "Hello Server!"
  end

end