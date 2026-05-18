require 'socket' # rubocop:disable Style/FrozenStringLiteralComment
require 'json'

class TcpWebSocketClient
  DELIMITER = -"\n"

  def initialize(host, port, on_connect:, on_message:, on_error:, on_disconnect:) # rubocop:disable Metrics/ParameterLists
    @host = host
    @port = port
    @on_connect = on_connect
    @on_message = on_message
    @on_error = on_error
    @on_disconnect = on_disconnect

    @socket = nil
    @listener_thread = nil
    @mtx = Mutex.new
  end

  def connect
    begin
      @socket = TCPSocket.new(@host, @port)
    rescue StandardError => e
      @on_error.call(e)
      return
    end

    @on_connect.call

    @listener_thread = Thread.new do
      loop do
        line = @socket.gets(DELIMITER)
        break if line.nil?

        @on_message.call(line.chomp)
      end
    rescue StandardError => e
      @on_error.call(e)
    ensure
      @on_disconnect.call
    end
  end

  def send_msg(msg)
    @mtx.synchronize do
      @socket.puts(msg + DELIMITER)
    end
  rescue StandardError => e
    @on_error.call(e)
  end

  def wait
    @listener_thread&.join
  end

  def close
    @socket&.close
  end
end
