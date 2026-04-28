require 'websocket-eventmachine-server' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative './game'

# Game server that handles the separate threads for running the game
class Server
  def run_event_machine
    EM.run do
      WebSocket::EventMachine::Server.start(host: '0.0.0.0', port: 25_252) do |ws|
        ws.onopen do
          # TODO: Handle player rejoining mid-game
          # TODO Trigger game chooser for client
          @game ||= Game.new('Sample_Hearts.json')
          @game.add_player(ws)

          start_tick_thread(30)
          start_game_thread
        end
      end
    end
  end

  def start_tick_thread(ticks_per_second)
    @tick_thread ||= Thread.new do # rubocop:disable Naming/MemoizedInstanceVariableName
      loop do
        @game.tick
        sleep(1.0 / ticks_per_second)
      end
    end
  end

  def start_game_thread
    @game_thread ||= Thread.new do # rubocop:disable Naming/MemoizedInstanceVariableName
      game_initiated = false
      until game_initiated
        sleep(10)
        @game.run_game
        game_initiated = @game.game_started
      end
    end
  end
end

server = Server.new
server.run_event_machine
