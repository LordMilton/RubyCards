require 'gosu' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment

# You need me to tell you what a button is?
class Button
  # PADDING_X     = 20   # horizontal padding between text and border
  # PADDING_Y     = 12   # vertical padding between text and border

  DEFAULT_FONT_SIZE = 20

  # Normal state colours
  BG_COLOR      = Gosu::Color.new(255, 60,  120, 220)   # blue
  BORDER_COLOR  = Gosu::Color.new(255, 120, 190, 255)   # lighter blue
  TEXT_COLOR    = Gosu::Color.new(255, 255, 255, 255)   # white

  # Disabled state colors
  BG_DISABLED      = Gosu::Color.new(150, 40,  80, 147)
  BORDER_DISABLED  = Gosu::Color.new(150, 80,  127, 170)
  TEXT_DISABLED    = Gosu::Color.new(150, 200, 200, 200)

  # Hover state colours
  BG_HOVER      = Gosu::Color.new(255, 90,  160, 255)
  BORDER_HOVER  = Gosu::Color.new(255, 180, 220, 255)

  # Z-layers
  Z_BG     = 0
  Z_BORDER = 1
  Z_TEXT   = 2

  BORDER_THICKNESS = 2

  attr_reader :label, :selectable

  # @param label      [String]        text shown on the button
  # @param position   [int[]]         Expected order [topLeftX, topLeftY, bottomRightX, bottomRightY]
  def initialize(label, position)
    @label = label
    @left_x = position[0]
    @top_y = position[1]
    @right_x = position[2]
    @bottom_y = position[3]
    @width = @right_x - @left_x
    @height = @bottom_y - @top_y
    @font = Gosu::Font.new(DEFAULT_FONT_SIZE)

    @selectable = false
  end

  # Draw the button
  # Automatically switches to a hover style when the cursor is over it.
  #
  # @param mouse_x [Numeric] current cursor x (pass window.mouse_x)
  # @param mouse_y [Numeric] current cursor y (pass window.mouse_y)
  def draw(mouse_x = nil, mouse_y = nil)
    hovering = mouse_x && mouse_y && clicked?(mouse_x, mouse_y)

    bg_color = BG_DISABLED
    border_color = BORDER_DISABLED
    label_color = TEXT_DISABLED
    if selectable
      label_color = TEXT_COLOR
      bg_color = BG_COLOR
      border_color = BORDER_COLOR
      if hovering
        bg_color = BG_HOVER
        border_color = BORDER_HOVER
      end
    end

    draw_background(bg_color)
    draw_border(border_color)
    draw_label(label_color)
  end

  def makeSelectable(selectable)
    @selectable = selectable
  end

  # Returns true when the given screen coordinates fall inside the button as long as the button is not disabled
  #
  # @param x [Numeric] x coordinate
  # @param y [Numeric] y coordinate
  # @return [Boolean]
  def clicked?(x, y)
    return(
      @selectable &&
      x >= @left_x &&
      x <= @right_x &&
      y >= @top_y &&
      y <= @bottom_y)
  end

  private

  def draw_background(color)
    Gosu.draw_rect(@left_x, @top_y, @width, @height, color)
  end

  def draw_border(color)
    t = BORDER_THICKNESS
    # Top
    Gosu.draw_rect(@left_x - t, @top_y - t, @width + (2 * t), t, color)
    # Bottom
    Gosu.draw_rect(@left_x - t, @bottom_y, @width + (2 * t), t, color)
    # Left
    Gosu.draw_rect(@left_x - t, @top_y - t, t, @height + (2 * t), color)
    # Right
    Gosu.draw_rect(@right_x, @top_y - t, t, @height + (2 * t), color)
  end

  def draw_label(color)
    text_w = @font.text_width(@label)
    text_h = @font.height

    # Scale to fit whichever dimension is the tighter constraint
    scale = [@width / text_w.to_f, @height / text_h.to_f].min

    scaled_w = text_w * scale
    scaled_h = text_h * scale

    text_x = @left_x + (@width - scaled_w) / 2.0
    text_y = @top_y  + (@height - scaled_h) / 2.0

    @font.draw_text(@label, text_x, text_y, Z_TEXT, scale, scale, color)
  end
end

if __FILE__ == $PROGRAM_NAME
  class DemoWindow < Gosu::Window
    def initialize
      super(640, 480, false)
      self.caption = "Button Demo"

      @buttons = [
        Button.new("Enable/Disable", [200, 160, 350, 200]),
        Button.new("Submit", [200, 230, 440, 280]),
        Button.new("Cancel", [200, 305, 350, 345])
      ]
      @buttons[0].makeSelectable(true)

      @message = "Hover over a button, then click it."
    end

    def update; end

    def draw
      @buttons.each { |btn| btn.draw(mouse_x, mouse_y) }

      # Display feedback message at the bottom
      Gosu::Font.new(18).draw_text(@message, 20, 440, 10,
                                   1, 1, Gosu::Color::WHITE)
    end

    def button_down(id)
      if id == Gosu::MS_LEFT
        @buttons.each do |btn|
          if btn.clicked?(mouse_x, mouse_y)
            if(btn.label == "Enable/Disable")
              @buttons[1].makeSelectable(!@buttons[1].selectable)
              @buttons[2].makeSelectable(!@buttons[2].selectable)
            end
            @message = "\"#{btn.label}\" clicked at (#{mouse_x.to_i}, #{mouse_y.to_i})"
          end
        end
      end
      close if id == Gosu::KB_ESCAPE
    end
  end

  DemoWindow.new.show
end