require 'gosu' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative '../logger'
require_relative './button'
require_relative '../cards/hand'
require_relative './locator'
require_relative './window'

LOCATION = {
  'S' => 0,
  'W' => 1,
  'N' => 2,
  'E' => 3
}.freeze

DEFAULT_NAMES = {
  'S' => 'South',
  'W' => 'West',
  'N' => 'North',
  'E' => 'East'
}.freeze

def num_to_direction_hash(num)
  dirs = LOCATION.keys
  dirs[num % dirs.size]
end

class GameMaster
  include MyLogger

  BASE_SCREEN_SIZE = [1920, 1080].freeze

  def initialize(websocket, card_drawer)
    @websocket = websocket
    @card_drawer = card_drawer
    @player_positions_clockwise_from_front = [num_to_direction_hash(0),
                                              num_to_direction_hash(1),
                                              num_to_direction_hash(2),
                                              num_to_direction_hash(3)]
    # Assumes a 1920,1080 screen, can adjust from there by ratio of new screen sizes
    # TODO: Allow different screen sizes
    @locator = Locator.new(BASE_SCREEN_SIZE)

    @player_hand_locations = nil
    @play_area_locations = nil
    @won_cards_locations = nil
    set_player_card_locations
    @play_areas_visible = true
    @won_cards_visible = true
    @deck_location = @locator.deck_location
    create_deck(0)
    @deck_visible = true
    @discard_location = @locator.discard_location
    create_discard
    @discard_visible = true
    @front_player = num_to_direction_hash(0)
    @player_hands = {}
    @play_areas = {}
    @won_cards = {}
    @connected_players = []
    @player_names_drawers = {}

    @cur_actionables = {}

    @button_labels = %w[Draw Play Discard]
    @buttons = @locator.button_locations(@button_labels)
    @buttons.each do |name, location|
      @buttons[name] = Button.new(name.capitalize, location)
    end

    @game_title_callback = nil
    @game_name = ''
  end

  def handle_first_frame
    @card_drawer.initialize_images
  end

  def create_deck(size)
    @deck = Hand.new('Deck')
    num_cards = size
    while num_cards.positive?
      @deck.add(Card.new(nil, nil, @card_drawer))
      num_cards -= 1
    end
    @deck.location(@deck_location)
  end

  def add_to_deck(card)
    @deck.add(card)
  end

  def remove_from_deck(index = 0)
    @deck.remove(index)
  end

  def deck_selectable(selectable)
    @deck.selectable(selectable)
  end

  def deck_visible(visible)
    @deck_visible = visible
  end

  def create_discard(cards = Hand.new('Discard'))
    cards.location(@discard_location)
    @discard = cards
  end

  def add_to_discard(card)
    @discard.add(card)
  end

  def remove_from_discard(index)
    @discard.remove(index)
  end

  def discard_selectable(selectable)
    @discard.selectable(selectable)
  end

  def discard_visible(visible)
    @discard_visible = visible
  end

  def create_player_hand(hash_dir, hand = Hand.new('Hand'))
    if player_slot_exists?(hash_dir)
      @player_hands[hash_dir] ||= hand
      reposition_hands
      return true
    end
    false
  end
  private :create_player_hand

  def add_to_hand(hash_dir, card)
    if player_slot_exists?(hash_dir)
      @player_hands[hash_dir].add(card)
      return true
    end
    false
  end

  def remove_from_hand(hash_dir, index)
    return @player_hands[hash_dir].remove(index) if player_slot_exists?(hash_dir)

    nil
  end

  def create_play_area(hash_dir, hand = Hand.new('Play Area'))
    if player_slot_exists?(hash_dir)
      @play_areas[hash_dir] ||= hand
      reposition_hands
      return true
    end
    false
  end
  private :create_play_area

  def play_areas_visible(visible)
    @play_areas_visible = visible
  end

  def add_to_play_area(hash_dir, card)
    if player_slot_exists?(hash_dir)
      @play_areas[hash_dir].add(card)
      return true
    end
    false
  end

  def remove_from_play_area(hash_dir, index)
    return @play_areas[hash_dir].remove(index) if player_slot_exists?(hash_dir)

    nil
  end

  def create_won_cards(hash_dir, hand = Hand.new('Cards Won'))
    if player_slot_exists?(hash_dir)
      @won_cards[hash_dir] ||= hand
      reposition_hands
      return true
    end
    false
  end
  private :create_won_cards

  def won_cards_visible(visible)
    @won_cards_visible = visible
  end

  def add_to_won_cards(hash_dir, card)
    if player_slot_exists?(hash_dir)
      @won_cards[hash_dir].add(card)
      return true
    end
    false
  end

  def remove_from_won_cards(hash_dir, index)
    return @won_cards[hash_dir].remove(index) if player_slot_exists?(hash_dir)

    nil
  end

  def add_actionable(actionable, count)
    logger.debug("Adding potential actionable: #{actionable}")
    @cur_actionables[actionable] = count
    if %w[play discard].include?(actionable)
      front_player_hand.selectable(true)
    elsif actionable == 'draw'
      deck_selectable(true)
    end
  end

  def reset_actionables
    @cur_actionables = {}
    @player_hands.each_value do |hand|
      hand.selectable(false)
    end
    @buttons.each_value do |button|
      button.makeSelectable(false)
    end
    deck_selectable(false)
    discard_selectable(false)
  end

  # @param callback (String) => nil
  def game_title_callback(callback)
    @game_title_callback = callback
    set_game_title
  end

  def set_front_player(hash_dir)
    logger.debug("Setting position #{hash_dir} to be the front player")
    if player_slot_exists?(hash_dir)
      difference = (LOCATION[hash_dir] - LOCATION[@front_player])
      @player_positions_clockwise_from_front.map! { |pos| num_to_direction_hash(LOCATION[pos] + difference) }
      set_player_card_locations
      @front_player = hash_dir
      reposition_hands
      set_game_title
      return true
    end
    false
  end

  def player_connected(player_dir)
    logger.debug("Including player slot #{player_dir} in game")
    if !@connected_players.include?(player_dir)
      @connected_players.append(player_dir)
      create_player_hand(player_dir)
      create_play_area(player_dir)
      create_won_cards(player_dir)
    else
      logger.debug('Ignoring duplicate player connected')
    end
    reposition_hands
  end

  def player_disconnected(player_dir)
    @connected_players.delete(player_dir)
    reposition_hands
  end

  def draw_game(mouse_x, mouse_y)
    # puts('drawing frame')
    @player_hands.each_value do |hand|
      # puts('drawing hand')
      hand.draw(mouse_x, mouse_y)
    end
    @player_names_drawers.each_value do |draw_fun|
      # puts('drawing name')
      draw_fun.call
    end
    if @play_areas_visible
      @play_areas.each_value do |play_area|
        # puts('drawing play area')
        play_area.draw(mouse_x, mouse_y)
      end
    end
    if @won_cards_visible
      @won_cards.each_value do |won_cards|
        # puts('drawing won cards')
        won_cards.draw(mouse_x, mouse_y)
      end
    end
    if !@deck.nil? && @deck_visible
      # puts('drawing deck')
      @deck.draw(mouse_x, mouse_y)
    end
    if !@discard.nil? && @discard_visible
      # puts('drawing discard')
      @discard.draw(mouse_x, mouse_y)
    end
    @buttons.each_value do |btn|
      # puts('drawing button')
      btn.draw(mouse_x, mouse_y)
    end
  end

  def clicked(mouse_x, mouse_y)
    card_clicked = false
    @player_hands.each_value do |hand|
      card_clicked ||= hand.clicked(mouse_x, mouse_y)
    end
    @play_areas.each_value do |hand|
      card_clicked ||= hand.clicked(mouse_x, mouse_y)
    end
    @won_cards.each_value do |hand|
      card_clicked ||= hand.clicked(mouse_x, mouse_y)
    end
    card_clicked ||= @deck.clicked(mouse_x, mouse_y) if @deck_visible
    card_clicked ||= @discard.clicked(mouse_x, mouse_y) if @discard_visible
    @buttons.each do |actionable, button|
      button_clicked = button.clicked?(mouse_x, mouse_y)
      next unless button_clicked

      msg = { 'action' => actionable }
      if actionable == 'draw'
        msg['subject'] = 'deck'
      else
        msg['subject'] = 'hand'
        msg['index'] = front_player_hand.selected_card_indexes
      end
      send_message(msg)
      reset_actionables
    end

    return unless card_clicked

    enable_disable_buttons
  end

  private

  def set_game_title
    return if @game_title_callback.nil?

    @game_title_callback.call("#{@game_name} (#{DEFAULT_NAMES[@front_player]})")
  end

  def front_player_hand
    @player_hands[@front_player]
  end

  def set_player_card_locations
    @player_hand_locations = @locator.player_hand_locations(@player_positions_clockwise_from_front)
    @play_area_locations = @locator.play_area_locations(@player_positions_clockwise_from_front)
    @won_cards_locations = @locator.won_cards_locations(@player_positions_clockwise_from_front)
  end

  def reposition_hands
    @player_hand_locations.each do |hand_key, location|
      hand = @player_hands[hand_key]
      hand&.location(location)
    end
    @play_area_locations.each do |hand_key, location|
      play_area = @play_areas[hand_key]
      play_area&.location(location)
    end
    @won_cards_locations.each do |hand_key, location|
      won_cards = @won_cards[hand_key]
      won_cards&.location(location)
    end
    dir_names_hash = {}
    logger.debug("Connected player slots: #{@connected_players}")
    @player_positions_clockwise_from_front.each do |dir|
      dir_names_hash[dir] = @connected_players.include?(dir) ? DEFAULT_NAMES[dir] : ''
    end
    @player_names_drawers = @locator.player_name_drawers(dir_names_hash)
  end

  def player_slot_exists?(hash_dir)
    @player_hand_locations.key?(hash_dir)
  end

  # Enable or disable buttons based on the currently expected actionables
  def enable_disable_buttons
    # Should assume buttons can't be used unless there's an associated actionable active
    @buttons.each_value do |button|
      button.makeSelectable(false)
    end

    @cur_actionables.each do |action, count|
      hand_to_check = (action == 'draw' ? @deck : front_player_hand)
      selected_in_hand_to_check = hand_to_check.selected_cards
      @buttons[action].makeSelectable(true) if selected_in_hand_to_check.size == count
    end
  end

  def send_message(msg_hash)
    @websocket.send(JSON.generate(msg_hash))
  end
end

if __FILE__ == $PROGRAM_NAME
  sample_card_drawer = CardDrawer.new('../../resources/cards')
  gm = GameMaster.new(nil, sample_card_drawer)
  players = %w[S E N W]
  hand_num = 2 # Current card value for card to put in card areas, differentiates hand directions
  players.each do |hand_key|
    gm.player_connected(hand_key)
    num_cards = 5
    while num_cards.positive?
      hand_card = Card.new(nil, nil, sample_card_drawer)
      played_card = Card.new(nil, nil, sample_card_drawer)
      won_card = Card.new(nil, nil, sample_card_drawer)
      gm.add_to_hand(hand_key, hand_card)
      gm.add_to_play_area(hand_key, played_card)
      gm.add_to_won_cards(hand_key, won_card)
      num_cards -= 1
    end

    hand_num += 1
  end
  # make stuff selectable
  gm.add_actionable('play', 1)
  gm.add_actionable('draw', 1)

  gm.create_deck(52)
  discard = Hand.new('Discard')
  discard_size = 6
  while discard_size.positive?
    discard.add(Card.new('hearts', 'king', sample_card_drawer))
    discard_size -= 1
  end
  gm.create_discard(discard)

  gm.discard_visible(true)
  gm.deck_visible(true)
  gm.play_areas_visible(false)
  gm.won_cards_visible(true)

  window = GameWindow.new(gm).show
end
