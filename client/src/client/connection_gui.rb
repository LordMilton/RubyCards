require 'gosu'
require 'socket'
require_relative '../logger'
require_relative '../ui/button'
require_relative '../ui/text_box'

class ConnectionGui
  include MyLogger

  def initialize(connect_callback)
    @connect_callback = connect_callback
    @error_message = nil
    @connecting = false
    @title_set = false

    @ip_box   = TextBox.new(200, 150, 300, 40,
                            initial_text: 'localhost')
    @port_box = TextBox.new(200, 250, 150, 40,
                            initial_text: '25252',
                            allowed_chars: /[0-9]/)

    @connect_button = Button.new('Connect', [200, 350, 200 + 200, 350 + 50])

    @font_large = Gosu::Font.new(28)
    @font = Gosu::Font.new(20)
  end

  def game_title_callback(callback)
    @title_callback = callback
    @title_callback = callback.call('Connect to Server')
  end

  def handle_first_frame
    @error_message = nil
    @connecting = false
  end

  def draw_ui(window)
    Gosu.draw_rect(0, 0, window.width, window.height, Gosu::Color::BLACK, 0)

    @font_large.draw_text('Connect to Server', 200, 50, 1, 1, 1, Gosu::Color::WHITE)

    @font.draw_text('IP Address:', 200, 110, 1, 1, 1, Gosu::Color::WHITE)
    @ip_box.draw

    @font.draw_text('Port:', 200, 210, 1, 1, 1, Gosu::Color::WHITE)
    @port_box.draw

    @connect_button.makeSelectable(true)
    @connect_button.draw

    return unless @error_message

    @font.draw_text(@error_message, 200, 450, 1, 1, 1, Gosu::Color.new(255, 255, 80, 80))
  end

  def button_down(id, window)
    case id
    when Gosu::KB_TAB
      if @ip_box.equal?(active_box)
        @ip_box.deactivate
        @port_box.activate(window)
      else
        @port_box.deactivate
        @ip_box.activate(window)
      end
    when Gosu::MS_LEFT
      Thread.new do # Start a new thread here, else the websocket will occupy the gosu tick thread
        attempt_connection if @connect_button.clicked?(window.mouse_x, window.mouse_y)
      end
    end

    @ip_box.button_down(id, window)
    @port_box.button_down(id, window)
  end

  private

  def active_box
    [@ip_box, @port_box].find { |b| b.equal?(b) && window_has_box?(b) }
  end

  def window_has_box?(box)
    # We track active state via the TextBox itself
    box.instance_variable_get(:@active)
  end

  def attempt_connection
    return if @connecting

    @connecting = true
    @error_message = nil

    port_int = Integer(@port_box.text)
    ip = @ip_box.text
    begin
      socket = TCPSocket.new(ip, port_int)
      socket.close
      @connecting = false
      @connect_callback.call(ip, port_int)
    rescue StandardError => e
      @error_message = "Failed to connect to server at #{ip}:#{port_int}: #{e.message}"
      @connecting = false
    end
  end
end
