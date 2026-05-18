require 'socket' # rubocop:disable Style/FrozenStringLiteralComment

class TcpClientConnection
  include MyLogger

  DELIMITER = -"\n"

  def initialize(socket)
    @socket = socket
    @mtx = Mutex.new
  end

  def send(msg)
    @mtx.synchronize do
      @socket.puts("#{msg}#{DELIMITER}")
    end
  rescue StandardError => e
    logger.error("Error sending message to client: #{e}")
  end

  def onmessage(&block)
    @on_message = block
  end

  def onclose(&block)
    @on_close = block
  end

  def listen
    Thread.new do
      loop do
        line = @socket.gets(DELIMITER)
        break if line.nil?

        @on_message&.call(line.chomp)
      end
    rescue StandardError => e
      logger.error("Client disconnected with error: #{e}")
    ensure
      @on_close&.call
      @socket.close
    end
  end
end
