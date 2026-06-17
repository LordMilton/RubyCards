require 'gosu'
require 'socket'

class TextBox
  attr_reader :text

  def initialize(x, y, w, h, initial_text: '', allowed_chars: /.*/)
    @x = x
    @y = y
    @w = w
    @h = h
    @allowed_chars = allowed_chars
    @active = false
    @font = Gosu::Font.new(20)

    @text_input = Gosu::TextInput.new
    @text_input.text = initial_text
  end

  def text
    @text_input.text
  end

  def activate(window)
    @active = true
    window.text_input = @text_input
  end

  def deactivate
    @active = false
  end

  def draw
    bg_color = Gosu::Color.new(255, 50, 50, 60)
    border_color = @active ? Gosu::Color.new(255, 100, 200, 100) : Gosu::Color::WHITE

    Gosu.draw_rect(@x, @y, @w, @h, bg_color, 0)

    t = 2
    Gosu.draw_rect(@x,         @y, @w, t, border_color, 1)
    Gosu.draw_rect(@x,         @y + @h - t, @w, t, border_color, 1)
    Gosu.draw_rect(@x,         @y,         t, @h, border_color, 1)
    Gosu.draw_rect(@x + @w - t, @y,        t, @h, border_color, 1)

    display_text = @active ? text_with_cursor : @text_input.text
    @font.draw_text(display_text, @x + 10, @y + (@h - @font.height) / 2, 2, 1, 1, Gosu::Color::WHITE)
  end

  def button_down(id, window)
    case id
    when Gosu::MS_LEFT
      if clicked?(window.mouse_x, window.mouse_y)
        activate(window)
      else
        deactivate
      end
    end
    return unless @active

    enforce_allowed_chars
  end

  private

  def clicked?(mouse_x, mouse_y)
    mouse_x >= @x && mouse_x <= @x + @w &&
      mouse_y >= @y && mouse_y <= @y + @h
  end

  def text_with_cursor
    t = @text_input.text
    pos = @text_input.caret_pos
    "#{t[0...pos]}|#{t[pos..]}"
  end

  def enforce_allowed_chars
    filtered = @text_input.text.chars.select { |c| c.match?(@allowed_chars) }.join
    @text_input.text = filtered
  end
end
