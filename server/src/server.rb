require_relative './game' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative './logger'
require_relative './tcp_client_handler'

# Game server that handles the separate threads for running the game
class Server
  include MyLogger

  def run_tcp_server(host = '0.0.0.0', port = 25252) # rubocop:disable Style/NumericLiterals
    logger.info "Starting local server on #{port}"
    begin
      @server = TCPServer.new(host, port)
    rescue Errno::EADDRINUSE
      logger.fatal("Port #{port} is already occupied, cannot start server")
      return
    end

    loop do
      Thread.new(@server.accept) do |socket|
        ws = TcpClientConnection.new(socket)

        @game ||= Game.new('Sample_Hearts.json')
        @game.add_player(ws)

        start_tick_thread(30)
        start_game_thread

        ws.listen.join
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

game_server = Server.new
game_server.run_tcp_server
