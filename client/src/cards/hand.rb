require 'concurrent' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative '../logger'

# Represents a hand of cards
class Hand
  include MyLogger

  attr_reader :cards

  BORDER_THICKNESS = 2.0

  HOVER_TEXT_SIZE = 22.0
  NAME_TEXT_SIZE = 40.0
  NAME_INNER_EDGE_BUFFER = 1.0

  def initialize(name)
    @cards = []
    @selectable = false

    @name = name
    @name_image = nil

    @hover_text = ''
    @hover_text_image = nil
    @hover_text_rw_lock = Concurrent::ReadWriteLock.new

    # Creating any kind of Gosu::Image before the Gosu::Window exists seems to cause a black screen
    # If draw() has been called, we can be confident that Gosu::Window exists
    @draw_called = false

    # Drawing values
    @left_x = 0
    @top_y = 0
    @right_x = 0
    @bottom_y = 0
    @start_x = 0
    @card_spacing = 0
    @card_scaling = 0
  end

  # Expected order [left_x, top_y, right_x, bottom_y]
  def location(position)
    if position.respond_to?('each') && position.respond_to?('size') && position.size == 4
      @left_x = position[0]
      @top_y = position[1]
      @right_x = position[2]
      @bottom_y = position[3]
      calculate_drawing(@left_x, @top_y, @right_x, @bottom_y)
    else
      puts('location given invalid argument: not iterable or not containing 4 elements')
    end
  end

  def selectable(selectable)
    @selectable = selectable
    @cards.each do |card|
      card.make_selectable(@selectable)
    end
  end

  def selected_cards
    @cards.select(&:selected)
  end

  def selected_card_indexes
    selected_indexes = []
    @cards.each_index do |index|
      selected_indexes.append(index) if @cards[index].selected
    end
    selected_indexes
  end

  def clicked(click_x, click_y)
    click_within_bounds = false
    if point_within_bounds?(click_x, click_y)
      click_within_bounds = true
      if @selectable
        @cards.reverse_each do |card|
          break if card.clicked(click_x, click_y)
        end
      end
    end
    click_within_bounds
  end

  def select(index)
    @cards[index] || nil
  end

  def add(card)
    card.make_selectable(@selectable)
    @cards.append(card)
    calculate_drawing_same_location
  end

  def remove(index)
    removed = @cards.delete_at(index)
    calculate_drawing_same_location
    removed
  end

  def draw(mouse_x, mouse_y)
    unless @draw_called
      @draw_called = true
      fix_hover_text
    end

    draw_name if @cards.empty?
    draw_border

    hover_text_drawer = nil
    @cards.each do |card|
      card.draw(mouse_x, mouse_y)
      new_hover_text_drawer = card.hover_text_drawer(mouse_x, mouse_y)
      hover_text_drawer = new_hover_text_drawer.nil? ? hover_text_drawer : new_hover_text_drawer
    end
    if !hover_text_drawer.nil?
      hover_text_drawer.call
    elsif point_within_bounds?(mouse_x, mouse_y)
      draw_hover_text(mouse_x, mouse_y)
    end
  end

  private

  def draw_border
    color = Gosu::Color::WHITE
    t = BORDER_THICKNESS
    width = @right_x - @left_x
    height = @bottom_y - @top_y
    # Top
    Gosu.draw_rect(@left_x - t, @top_y - t, width + (2 * t), t, color)
    # Bottom
    Gosu.draw_rect(@left_x - t, @bottom_y, width + (2 * t), t, color)
    # Left
    Gosu.draw_rect(@left_x - t, @top_y - t, t, height + (2 * t), color)
    # Right
    Gosu.draw_rect(@right_x, @top_y - t, t, height + (2 * t), color)
  end

  def draw_name
    @name_image ||= Gosu::Image.from_text(@name, NAME_TEXT_SIZE)

    # within a^2 + a^2 = c^2
    a = NAME_TEXT_SIZE / Math.sqrt(2)

    top_left_x = @left_x + a + NAME_INNER_EDGE_BUFFER
    top_left_y = @top_y + NAME_INNER_EDGE_BUFFER
    top_right_x = @right_x - NAME_INNER_EDGE_BUFFER
    top_right_y = @bottom_y - a - NAME_INNER_EDGE_BUFFER
    bottom_left_x = @left_x + NAME_INNER_EDGE_BUFFER
    bottom_left_y = @top_y + a + NAME_INNER_EDGE_BUFFER
    bottom_right_x = @right_x - a - NAME_INNER_EDGE_BUFFER
    bottom_right_y = @bottom_y + NAME_INNER_EDGE_BUFFER

    color = Gosu::Color::WHITE
    @name_image.draw_as_quad(
      top_left_x,     top_left_y,     color,
      top_right_x,    top_right_y,    color,
      bottom_left_x,  bottom_left_y,  color,
      bottom_right_x, bottom_right_y, color,
      0.9
    )
  end

  def draw_hover_text(mouse_x, mouse_y)
    @hover_text_rw_lock.with_write_lock do
      @hover_text_image ||= Gosu::Image.from_text(@hover_text, HOVER_TEXT_SIZE)
      return if @hover_text_image.nil?

      @hover_text_image.draw(mouse_x, mouse_y + 15, 1)
    end
  end

  def fix_hover_text
    @hover_text_rw_lock.with_write_lock do
      new_hover_text = "#{@cards.size} " + (@cards.size == 1 ? 'Card' : 'Cards')
      return unless @hover_text_image.nil? || @hover_text != new_hover_text

      @hover_text = new_hover_text
      logger.debug("Set hover text to be \"#{@hover_text}\"")
      @hover_text_image = nil
    end
  end

  def calculate_drawing_same_location
    calculate_drawing(@left_x, @top_y, @right_x, @bottom_y)
  end

  def calculate_drawing(left_x, top_y, right_x, bottom_y)
    return if left_x.nil? || top_y.nil? || right_x.nil? || bottom_y.nil?

    fix_hover_text
    if @cards.empty?
      @start_x = 0
      @card_spacing = 0
      @card_scaling = 0
    else
      sample_card = @cards[0].image

      center_x = (left_x + right_x) / 2
      # center_y = (top_y + bottom_y) / 2
      hand_draw_height = bottom_y - top_y
      hand_draw_width = right_x - left_x
      card_scaling = hand_draw_height * 1.0 / sample_card.height

      @card_width = sample_card.width * card_scaling
      @card_height = sample_card.height * card_scaling
      effective_hand_width = [hand_draw_width - @card_width, 0].max # If the width is less than 0, the hand gets drawn backwards

      if @card_width * @cards.size < effective_hand_width
        @card_spacing = @card_width
        @start_x = center_x - (@card_width * @cards.size / 2.0)
      elsif @cards.size == 1
        @card_spacing = 0
        @start_x = left_x
      else
        @card_spacing = effective_hand_width * 1.0 / (@cards.size - 1)
        @start_x = left_x
      end

      update_card_locations
    end
  end

  def update_card_locations
    next_x = @start_x
    @cards.each do |card|
      card.set_drawing_info(next_x, @top_y, @card_width, @card_height)
      next_x += @card_spacing
    end
  end

  def point_within_bounds?(screen_x, screen_y)
    return false if @left_x.nil? || @right_x.nil? || @top_y.nil? || @bottom_y.nil?

    @left_x <= screen_x &&
      @right_x >= screen_x &&
      @top_y <= screen_y &&
      @bottom_y >= screen_y
  end
end
