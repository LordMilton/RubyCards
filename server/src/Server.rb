require "websocket-eventmachine-server"
require_relative "./Game"

class Server
  def initialize()
    @numPlayers = 0

    EM.run do

      WebSocket::EventMachine::Server.start(:host => "0.0.0.0", :port => 25252) do |ws|
        ws.onopen do
          @numPlayers += 1
          #TODO Trigger game chooser for client
          @game ||= Game.new("Sample_Hearts.json")
          @game.addPlayer(ws)
        end

        ws.onmessage do |msg, type|
          puts "Received message: #{msg}"
          @game.receivedMessage(msg)
        end

        ws.onclose do
          # TODO Will need to handle client disconnects at some point
          puts "Client disconnected"
        end
      end
    end
  end
end

Server.new()