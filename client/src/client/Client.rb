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
cardDrawer = nil

websocketMtx = Mutex.new

EM.run do

  ws = WebSocket::EventMachine::Client.connect(:uri => 'ws://localhost:25252')

  ws.onopen do
    websocketMtx.synchronize {
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
    }
  end

  ws.onmessage do |msgJson, type|
    websocketMtx.synchronize {
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
        when "add_card"
          card = msg["card"]
          suit = card["suit"]
          value = card["value"]
          newCard = Card.new(suit, value, cardDrawer)

          subject = nil
          case msg["subject"]
          when "deck"
            gameMaster.addToDeck(newCard)
          when "discard"
            gameMaster.addToDiscard(newCard)
          when "hand"
            gameMaster.addToHand(msg["subjectSpecifier"], newCard)
          when "play_area"
            gameMaster.addToPlayArea(msg["subjectSpecifier"], newCard)
          else
            logger.warn("Received add_card message with unknown subject #{msg["subject"]}")
          end
        when "remove_card"
          index = msg["index"]

          subject = nil
          case msg["subject"]
          when "deck"
            gameMaster.removeFromDeck(index)
          when "discard"
            gameMaster.removeFromDiscard(index)
          when "hand"
            gameMaster.removeFromHand(msg["subjectSpecifier"], index)
          when "play_area"
            gameMaster.removeFromPlayArea(msg["subjectSpecifier"], index)
          else
            logger.warn("Received remove_card message with unknown subject #{msg["subject"]}")
          end
        else
          logger.warn("Received action message with unknown type #{msg["type"]}")
        end
      when "actionable"
        gameMaster.resetActionables()

        actionables = msg["msg"]["actionables"]
        actionPrefix = "action_"
        curActionNum = 1
        curAction = actionables["#{actionPrefix}#{curActionNum}"]
        actionsRemaining = true
        while(actionsRemaining)
          logger.info("Adding potential actionable: #{curAction}")
          gameMaster.addActionable(curAction["action"], curAction["count"])

          curActionNum += 1
          curAction = actionables["#{actionPrefix}#{curActionNum}"]
          actionsRemaining = (curAction != nil)
        end
      when "info"
        msg = msg["msg"]
        case msg["type"]
        when "set_visibility"
          visible = msg["visible"] == "true" ? true : false
          case msg["subject"]
          when "deck"
            gameMaster.makeDeckVisible(visible)
          when "discard"
            gameMaster.makeDiscardVisible(visible)
          else
            logger.warn("Received set_visibility message with unknown subject #{msg["subject"]}")
          end
        else
          logger.warn("Received info message with unknown type #{msg["type"]}")
        end
      else
        logger.warn("Received message with an unknown type #{msg["type"]}")
      end

    }
  end

  ws.onclose do |code, reason|
    logger.debug("Disconnected with status code: #{code}")
    exit
  end

end