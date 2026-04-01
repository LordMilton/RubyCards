require "websocket-eventmachine-server"
require_relative "./Game"

class Server
  def initialize()
  end

  def runEM()
    EM.run do

      WebSocket::EventMachine::Server.start(:host => "0.0.0.0", :port => 25252) do |ws|
        
        ws.onopen do
          # TODO Handle player joining mid-game
          # TODO Trigger game chooser for client
          @game ||= Game.new("Sample_Hearts.json")
          @game.addPlayer(ws)

          startTickThread(30)
        end

      end
    end
  end

  def startTickThread(ticksPerSecond)
    if(@tickThread == nil)
      @tickThread = Thread.new {
        while(true)
          @game.tick()
          sleep(1.0 / ticksPerSecond)
        end
      }
    end
  end
end

server = Server.new()
server.runEM()