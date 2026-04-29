# First line for rubocop disables # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment

# Calculates and provides location information for all visuals
class Locator
  BASE_SCREEN_SIZE = [1920.0, 1080.0].freeze

  PLAYER_HAND_HEIGHT = 175.0
  PLAYER_HAND_WIDTH = 400.0
  X_EDGE_BUFFER = 50.0
  Y_EDGE_BUFFER = 50.0

  PLAYER_NAME_HEIGHT_BUFFER = 10.0
  DESIRED_PLAYER_NAME_HEIGHT = 30.0

  DECK_HEIGHT = PLAYER_HAND_HEIGHT
  DECK_WIDTH = 125.0

  DISCARD_HEIGHT = PLAYER_HAND_HEIGHT
  DISCARD_WIDTH = 350.0

  WON_CARDS_BUFFER = 25.0

  DECK_AND_DISCARD_TOP = 450.0

  BUTTON_HEIGHT = 40.0
  BUTTON_WIDTH = 150.0
  BUTTON_HEIGHT_BUFFER = 10.0
  BUTTON_WIDTH_BUFFER = 10.0

  def initialize(screen_dimensions = BASE_SCREEN_SIZE)
    calculate_internal_dimensions(screen_dimensions)
  end

  def calculate_internal_dimensions(screen_dimensions)
    screen_width = screen_dimensions[0]
    screen_height = screen_dimensions[1]

    @x_screen_center = screen_width / 2
    @y_screen_center = screen_height / 2

    @x_ratio = BASE_SCREEN_SIZE[0] / screen_width
    @y_ratio = BASE_SCREEN_SIZE[1] / screen_height

    @actual_hand_width = PLAYER_HAND_WIDTH * @x_ratio
    @actual_hand_height = PLAYER_HAND_HEIGHT * @y_ratio

    @actual_deck_height = DECK_HEIGHT * @y_ratio
    @actual_deck_width = DECK_WIDTH * @x_ratio

    @actual_discard_height = DISCARD_HEIGHT * @y_ratio
    @actual_discard_width = DISCARD_WIDTH * @x_ratio

    # X dimensions for hands that are centered on the x axis
    @x_centered_hands_left = 750 * @x_ratio
    @x_centered_hands_right = @x_centered_hands_left + @actual_hand_width
    # Y dimensions for hands that are centered on the y axis
    @y_centered_hands_top = 450 * @y_ratio
    @y_centered_hands_bottom = @y_centered_hands_top + @actual_hand_height

    # X buffer from screen edge
    @x_buffer = X_EDGE_BUFFER * @x_ratio
    # Y buffer from screen edge
    @y_buffer = Y_EDGE_BUFFER * @y_ratio

    # Left hand x dimensions
    @left_hand_left = 0 + @x_buffer
    @left_hand_right = @left_hand_left + @actual_hand_width
    # Right hand x dimensions
    @right_hand_right = screen_width - @x_buffer
    @right_hand_left = @right_hand_right - @actual_hand_width
    # Top hand y dimensions
    @top_hand_top = 0 + @y_buffer
    @top_hand_bottom = @top_hand_top + @actual_hand_height
    # Bottom hand y dimensions
    @bottom_hand_bottom = screen_height - @y_buffer
    @bottom_hand_top = @bottom_hand_bottom - @actual_hand_height

    # Player name dimensions
    @actual_player_name_height_buffer = PLAYER_NAME_HEIGHT_BUFFER * @y_ratio
    @actual_player_name_height = DESIRED_PLAYER_NAME_HEIGHT * @y_ratio
    # Bottom player - above the bottom hand
    @bottom_name_x_center = (@x_centered_hands_left + @x_centered_hands_right) / 2.0
    @bottom_name_y_center = @bottom_hand_top - @actual_player_name_height_buffer - (@actual_player_name_height / 2)
    # Top player - below the top hand
    @top_name_x_center = (@x_centered_hands_left + @x_centered_hands_right) / 2.0
    @top_name_y_center = @top_hand_bottom + @actual_player_name_height_buffer + (@actual_player_name_height / 2)
    # Left player - above the left hand
    @left_name_x_center = (@left_hand_left + @left_hand_right) / 2.0
    @left_name_y_center = @y_centered_hands_top - @actual_player_name_height_buffer - (@actual_player_name_height / 2)
    # Right player - above the right hand
    @right_name_x_center = (@right_hand_left + @right_hand_right) / 2.0
    @right_name_y_center = @y_centered_hands_top - @actual_player_name_height_buffer - (@actual_player_name_height / 2)

    # Button dimensions
    @button_left_buffer = BUTTON_WIDTH_BUFFER * @x_ratio
    @button_top_buffer = BUTTON_HEIGHT_BUFFER * @y_ratio
    @button_left = @x_centered_hands_right + @button_left_buffer
    @button_right = @button_left + BUTTON_WIDTH
    @first_button_top = @bottom_hand_top

    # Play area dimensions
    @play_area_x_center_buffer = 100 * @x_ratio
    @play_area_y_center_buffer = 75 * @y_ratio
    @play_area_width = @actual_deck_width
    @play_area_height = @actual_deck_height
    # X dimensions for play areas that are centered on the x axis
    @x_centered_play_area_left = @x_screen_center - (@play_area_width / 2)
    @x_centered_play_area_right = @x_centered_play_area_left + @play_area_width
    # Y dimensions for play areas that are centered on the y axis
    @y_centered_play_area_top = @y_screen_center - (@play_area_height / 2)
    @y_centered_play_area_bottom = @y_centered_play_area_top + @play_area_height
    # Left play area x dimensions
    @left_play_area_right = @x_screen_center - @play_area_x_center_buffer
    @left_play_area_left = @left_play_area_right - @play_area_width
    # Right play area x dimensions
    @right_play_area_left = @x_screen_center + @play_area_x_center_buffer
    @right_play_area_right = @right_play_area_left + @play_area_width
    # Top play area y dimensions
    @top_play_area_bottom = @y_screen_center - @play_area_y_center_buffer
    @top_play_area_top = @top_play_area_bottom - @play_area_height
    # Bottom play area y dimensions
    @bottom_play_area_top = @y_screen_center + @play_area_y_center_buffer
    @bottom_play_area_bottom = @bottom_play_area_top + @play_area_height

    # Won Cards dimensions
    @won_cards_x_buffer = WON_CARDS_BUFFER * @x_ratio
    @won_cards_y_buffer = WON_CARDS_BUFFER * @y_ratio
    @won_cards_width = @actual_deck_width
    @won_cards_height = @actual_deck_height
    # Left Won Cards dimensions
    @left_won_cards_left = X_EDGE_BUFFER
    @left_won_cards_right = @left_won_cards_left + @won_cards_width
    @left_won_cards_top = @y_centered_hands_bottom + @won_cards_y_buffer
    @left_won_cards_bottom = @left_won_cards_top + @won_cards_height
    # Right Won Cards dimensions
    @right_won_cards_right = screen_width - X_EDGE_BUFFER
    @right_won_cards_left = @right_won_cards_right - @won_cards_width
    @right_won_cards_bottom = @y_centered_hands_top - @won_cards_y_buffer
    @right_won_cards_top = @right_won_cards_bottom - @won_cards_height
    # Top Won Cards dimensions
    @top_won_cards_right = @x_centered_hands_left - @won_cards_x_buffer
    @top_won_cards_left = @top_won_cards_right - @won_cards_width
    @top_won_cards_top = Y_EDGE_BUFFER
    @top_won_cards_bottom = @top_won_cards_top + @won_cards_height
    # Bottom Won Cards dimensions
    @bottom_won_cards_left = @button_right + @won_cards_x_buffer
    @bottom_won_cards_right = @bottom_won_cards_left + @won_cards_width
    @bottom_won_cards_bottom = screen_height - Y_EDGE_BUFFER
    @bottom_won_cards_top = @bottom_won_cards_bottom - @won_cards_height

    # Deck dimensions
    @deck_left = 700 * @x_ratio
    @deck_right = @deck_left + @actual_deck_width
    @deck_top = DECK_AND_DISCARD_TOP * @y_ratio
    @deck_bottom = @deck_top + @actual_deck_height

    # Discard dimensions
    @discard_left = 850 * @x_ratio
    @discard_right = @discard_left + @actual_discard_width
    @discard_top = DECK_AND_DISCARD_TOP * @y_ratio
    @discard_bottom = @discard_top + @actual_discard_height
  end
  private :calculate_internal_dimensions

  # names expected to start from bottom player and move clockwise
  def player_hand_locations(players)
    player_hand_locations = [
      [@x_centered_hands_left, @bottom_hand_top,      @x_centered_hands_right, @bottom_hand_bottom],
      [@left_hand_left,        @y_centered_hands_top, @left_hand_right,        @y_centered_hands_bottom],
      [@x_centered_hands_left, @top_hand_top,         @x_centered_hands_right, @top_hand_bottom],
      [@right_hand_left,       @y_centered_hands_top, @right_hand_right,       @y_centered_hands_bottom]
    ]
    player_hand_locations_hash = {}
    player_hand_locations.zip(players).each do |location, player|
      player_hand_locations_hash[player] = location
    end
    player_hand_locations_hash
  end

  # names expected to start from bottom player and move clockwise
  def play_area_locations(players)
    play_area_locations = [
      [@x_centered_play_area_left, @bottom_play_area_top,     @x_centered_play_area_right, @bottom_play_area_bottom],
      [@left_play_area_left,       @y_centered_play_area_top, @left_play_area_right,       @y_centered_play_area_bottom],
      [@x_centered_play_area_left, @top_play_area_top,        @x_centered_play_area_right, @top_play_area_bottom],
      [@right_play_area_left,      @y_centered_play_area_top, @right_play_area_right,      @y_centered_play_area_bottom]
    ]
    play_area_locations_hash = {}
    play_area_locations.zip(players).each do |location, player|
      play_area_locations_hash[player] = location
    end
    play_area_locations_hash
  end

  # names expected to start from bottom player and move clockwise
  def won_cards_locations(players)
    won_cards_locations = [
      [@bottom_won_cards_left, @bottom_won_cards_top, @bottom_won_cards_right, @bottom_won_cards_bottom],
      [@left_won_cards_left,   @left_won_cards_top,   @left_won_cards_right,   @left_won_cards_bottom],
      [@top_won_cards_left,    @top_won_cards_top,    @top_won_cards_right,    @top_won_cards_bottom],
      [@right_won_cards_left,  @right_won_cards_top,  @right_won_cards_right,  @right_won_cards_bottom]
    ]
    won_cards_locations_hash = {}
    won_cards_locations.zip(players).each do |location, player|
      won_cards_locations_hash[player] = location
    end
    won_cards_locations_hash
  end

  def deck_location
    [@deck_left, @deck_top, @deck_right, @deck_bottom]
  end

  def discard_location
    [@discard_left, @discard_top, @discard_right, @discard_bottom]
  end

  # first button name will be on top
  def button_locations(button_names)
    buttons = {}
    button_num = 0
    button_names.each do |name|
      this_button_top = @first_button_top + ((BUTTON_HEIGHT + BUTTON_HEIGHT_BUFFER) * button_num)
      this_button_bottom = this_button_top + BUTTON_HEIGHT
      buttons[name.downcase] = [@button_left, this_button_top, @button_right, this_button_bottom]
      button_num += 1
    end

    buttons
  end

  # @param dir_names_hash:Player names hashed by their direction. Order should be bottom player first moving clockwise
  # @return Functions which draw the player names provided, hashed in the same way the param was hashed
  def player_name_drawers(dir_names_hash)
    font_height = @actual_player_name_height.to_i
    # scale = @DesiredPlayerNameHeight / Gosu::Font.new.height
    name_font = Gosu::Font.new(font_height)
    text_drawers = {}
    text_drawers_array = [
      proc { |name| name_font.draw_text_rel(name, @bottom_name_x_center, @bottom_name_y_center, 1, 0.5, 0.5) },
      proc { |name| name_font.draw_text_rel(name, @left_name_x_center, @left_name_y_center, 1, 0.5, 0.5) },
      proc { |name| name_font.draw_text_rel(name, @top_name_x_center, @top_name_y_center, 1, 0.5, 0.5) },
      proc { |name| name_font.draw_text_rel(name, @right_name_x_center, @right_name_y_center, 1, 0.5, 0.5) }
    ]
    dir_names_hash.zip(text_drawers_array).each do |dir_name, text_drawer|
      key = dir_name[0]
      name = dir_name[1]
      text_drawers[key] = proc { text_drawer.call(name) }
    end
    text_drawers
  end
end
