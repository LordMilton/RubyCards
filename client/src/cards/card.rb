require_relative '../logger' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment

# Represents a Card in a deck
class Card
  include MyLogger

  HIGHLIGHT_SIZE_PX = 1

  attr_reader :suit, :value, :selected

  # @param suit:String Suit of the card
  # @param value:String Value of the card (string accounts for non-numeral cards)
  # @param card_drawer:CardDrawer Object for fetching card-related images
  def initialize(suit, value, card_drawer)
    @suit = suit
    @value = value
    @card_drawer = card_drawer
    @selected = false
    @selectable = false

    @left_x = nil
    @top_y = nil
    @right_x = nil
    @bottom_y = nil

    @image = nil
  end

  def hidden?
    @suit.nil? && @value.nil?
  end

  def make_selectable(selectable)
    @selectable = selectable
  end

  def clicked(click_x, click_y)
    click_within_bounds = false
    if point_within_bounds?(click_x, click_y)
      click_within_bounds = true
      toggle_selected
    end

    click_within_bounds
  end

  def set_drawing_info(left_x, top_y, width, height)
    @left_x = left_x
    @top_y = top_y
    @right_x = left_x + width
    @bottom_y = top_y + height
  end

  def draw(_mouse_x, _mouse_y)
    card_image = image
    if !card_image.nil?
      if @selected
        draw_rectangle(
          @card_drawer.highlight_image,
          @left_x - HIGHLIGHT_SIZE_PX,
          @top_y - HIGHLIGHT_SIZE_PX,
          @right_x + HIGHLIGHT_SIZE_PX,
          @bottom_y + HIGHLIGHT_SIZE_PX
        )
      end
      draw_rectangle(card_image, @left_x, @top_y, @right_x, @bottom_y)
    else
      logger.error("Tried to draw Card: #{suit} of #{@value}, but its image was null")
    end
  end

  def image
    @image ||= @card_drawer.card_image(self)
  end

  def hover_text_drawer(mouse_x, mouse_y)
    @hover_text ||= @card_drawer.card_hover_text(self, 22)

    if point_within_bounds?(mouse_x, mouse_y) && !@hover_text.nil?
      return proc {
        @hover_text.draw(mouse_x, mouse_y + 15, 1)
      }
    end

    nil
  end

  private

  def draw_rectangle(image, left_x, top_y, right_x, bottom_y)
    base_color = Gosu::Color.argb(0xff_ffffff)
    image.draw_as_quad(
      left_x, top_y, base_color,
      right_x, top_y, base_color,
      right_x, bottom_y, base_color,
      left_x, bottom_y, base_color,
      0
    )
  end

  def point_within_bounds?(screen_x, screen_y)
    @left_x <= screen_x && @right_x >= screen_x && @top_y <= screen_y && @bottom_y >= screen_y
  end

  def toggle_selected
    return unless @selectable

    @selected = !@selected
  end
end
