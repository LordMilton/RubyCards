require 'concurrent' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require 'json'
require_relative './card'
require_relative './message_builder'
require_relative './logger'
require_relative './trick_comparator'

LOCATION = {
  'S' => 0,
  'W' => 1,
  'N' => 2,
  'E' => 3
}.freeze

def num_to_direction_hash(num)
  dirs = LOCATION.keys
  dirs[num % dirs.size]
end

class Game
  include MyLogger

  attr_reader :game_started

  GAMES_FOLDER = -'../resources/games/'
  STEP_PREFIX = -'step_'

  # @param gamefile The filename for the instruction set (excluding the .json)
  def initialize(game_file)
    @rng = Random.new

    @game_started = false
    @game_instructions = JSON.parse(IO.read("#{GAMES_FOLDER}#{game_file}").gsub(/\r/, ' ').gsub(/\n/, ' '))
    @final_instruction_step = 0
    @players_ready = {}
    @players = {}
    @players_count = 0
    @players_scores = {}
    @hands = {}
    @play_areas = {}
    @won_cards = {}
    # Recent additions to any play areas, beggining is oldest, end is most recent
    # Items are array tuples: [player_direction, card]
    @recently_played = []
    @trick_comparator = nil
    @starting_deck = []
    set_starting_deck(@game_instructions['game']['deck'])
    @deck = []
    @discard = []

    # Data locks
    @players_rw_lock = Concurrent::ReadWriteLock.new
    @hands_rw_lock = Concurrent::ReadWriteLock.new

    # Visibility state
    @deck_visibility = false
    @discard_visibility = false

    # Special variables for use by the instructions during the game
    @last_winner = nil
    @cur_player = nil
    @last_dealer = nil

    # Variables for waiting on and handling client actions ("actionables")
    @actionable_latch = nil
    @cur_actionables = {}

    # Some variables to avoid having to pass around to/from helper functions
    @cur_step = 1
    @repeat_incrementers = {}

    # Message queues
    # TODO mutex?
    @outgoing_msg_q = []

    initialize_game
  end

  def run_game
    all_players_ready = false
    @players_rw_lock.with_read_lock do
      all_players_ready = !@players_ready.value?(false)
    end
    if !all_players_ready
      logger.debug('Not starting game until room is full')
    elsif @game_started
      logger.debug('Something tried to run the game an extra time')
    else
      logger.info('Starting game')

      @game_started = true

      game_complete = false

      presetup(@game_instructions) # Sets repeatIncrementers and final_instruction_step
      @deck_visibility = @game_instructions['game']['deck']['visible']
      indicate_deck_visibility
      @deck = @starting_deck
      indicate_deck

      set_starting_discard(@game_instructions['game']['discard'])

      until game_complete
        if @cur_step <= @final_instruction_step
          next_step_name = "#{STEP_PREFIX}#{@cur_step}"
          logger.info("Running step \"#{next_step_name}\"")
          run_step(@game_instructions[next_step_name.to_s])
          sleep(2)
        else
          logger.info('Game completed')
          game_complete = true
        end
      end
    end
  end

  # @param websocket The websocket connection to the player
  def add_player(websocket, player_dir = nil)
    logger.debug("Adding new player with requested direction: #{player_dir}") unless player_dir.nil?

    # Determine player's seat
    final_player_dir = nil
    @players_rw_lock.with_write_lock do
      if !player_dir.nil? && @players.any? { |player| player == player_dir }
        @players[player_dir] = websocket
        final_player_dir = player_dir
      elsif player_dir.nil?
        @players.each do |key, value|
          next unless value.nil?

          @players[key] = websocket
          final_player_dir = key
          break
        end

        logger.error("New client tried to join, but there's no room!") if final_player_dir.nil?
      else
        logger.error('New client connection provided invalid player direction')
      end
      logger.info("New client set to player position: #{final_player_dir}")
    end

    return if final_player_dir.nil?

    define_websocket_responses(websocket, final_player_dir)
    @players_count += 1

    return if @game_started

    run_game
  end

  def tick
    temp_outgoing_msg_q = @outgoing_msg_q
    @outgoing_msg_q = []
    temp_outgoing_msg_q.each do |item|
      msg = item[0]
      receiving_players = item[1]
      send_message(msg, receiving_players)
    end
  end

  private

  def initialize_game
    init_instructions = @game_instructions['game']
    @players_rw_lock.with_write_lock do
      @hands_rw_lock.with_write_lock do
        init_instructions['players'].each do |player|
          @players_ready[player] = false
          @players[player] = nil
          @players_scores[player] = 0
          @hands[player] = []
          @play_areas[player] = []
          @won_cards[player] = []
          @cur_player = player
          @last_dealer = get_previous_player(@cur_player)
        end
      end
    end
  end

  def presetup(instructions_hash)
    steps_complete = false
    current_step = 1
    until steps_complete
      current_step_instructions = instructions_hash["#{STEP_PREFIX}#{current_step}"]
      if !current_step_instructions.nil?
        if current_step_instructions['action'] == 'repeat_until' &&
           current_step_instructions['condition']['type'] == 'occurrences'
          @repeat_incrementers[current_step] = 0
        end
      else
        steps_complete = true
        @final_instruction_step = current_step - 1
      end

      current_step += 1
    end
  end

  def set_starting_deck(deck_instructions)
    cards = deck_instructions['cards']
    cards_list = cards['all']
    # card list with no differentiation between trump and fail cards
    if !cards_list.nil?
      cards_parsed = parse_card_list(cards_list)
      @starting_deck = cards_parsed['flat']
      @trick_comparator = TrickComparator.new(cards_parsed['hier'])
    else # card list with some level of trump (may be determined at the start of a hand)
      all_cards = []
      trump_list = cards['trump']
      logger.debug("trump_list: #{trump_list}")
      unless trump_list.nil?
        trump_parsed = parse_card_list(trump_list)
        trump_hier = trump_parsed['hier']
        trump_flat = trump_parsed['flat']
        all_cards.append(trump_flat)
      end
      fail_list = cards['fail']
      fail_parsed = parse_card_list(fail_list)
      fail_hier = fail_parsed['hier']
      fail_flat = fail_parsed['flat']
      all_cards.append(fail_flat)

      @trick_comparator = TrickComparator.new(trump_hier, fail_cards: fail_hier)

      logger.debug("setting starting deck to #{all_cards}")
      @starting_deck = all_cards.flatten
    end
  end

  def indicate_deck
    @deck.each do
      add_outgoing_message(MessageBuilder.build_add_card_message(nil, nil, 'deck'))
    end
  end

  def indicate_drawn_card(card, player_drawing, own_hand_hidden, other_hands_hidden)
    drawing_hand_suit = own_hand_hidden ? nil : card.suit
    drawing_hand_value = own_hand_hidden ? nil : card.value
    other_hands_suit = other_hands_hidden ? nil : card.suit
    other_hands_value = other_hands_hidden ? nil : card.value

    drawing_player_msg = MessageBuilder.build_add_card_message(drawing_hand_suit,
                                                               drawing_hand_value,
                                                               'hand',
                                                               player_drawing)
    other_player_msg = MessageBuilder.build_add_card_message(other_hands_suit,
                                                             other_hands_value,
                                                             'hand',
                                                             player_drawing)

    add_outgoing_message(drawing_player_msg, [player_drawing])
    add_outgoing_message(other_player_msg, get_other_players(player_drawing))
  end

  def add_outgoing_message(msg, receiving_players = connected_players())
    @outgoing_msg_q.push([msg, receiving_players])
  end

  def define_websocket_responses(websocket, player_dir)
    websocket.onmessage do |msg, _|
      logger.info("Received message from player_dir #{player_dir}")
      logger.debug("#{player_dir} message: #{msg}")
      received_message(msg, player_dir)
    end

    websocket.onclose do
      @players_rw_lock.with_write_lock do
        @players[player_dir] = nil
        @players_ready[player_dir] = false
        @players_count -= 1
      end
      indicate_player_disconnected(player_dir)
      logger.info("Player in seat #{player_dir} disconnected")
    end
  end

  def received_message(msg_json, player)
    msg = JSON.parse(msg_json)
    attempted_action = msg['action']
    if attempted_action.nil?
      logger.warning('Received message with no attempted action, ignoring...')
      return
    end

    # Check that a player isn't trying to play out of turn
    actionables_list = %w[draw play discard]
    if actionables_list.include?(attempted_action) && !@cur_player.nil? && player != @cur_player
      logger.warning("Player in slot #{player} tried to perform #{attempted_action} out of turn! Ignoring...")
      return
    end

    case attempted_action
    when 'request_place'
      logger.debug("Received #{msg['action']} message from player #{player}")
      handle_request_place_message(msg, player)
    when 'draw'
      logger.debug("Received #{msg['action']} message from player #{player}")
      handle_draw_message(msg, player)
    when 'play'
      logger.debug("Received #{msg['action']} message from player #{player}")
      handle_play_message(msg, player)
    when 'discard'
      logger.debug("Received #{msg['action']} message from player #{player}")
      handle_discard_message(msg, player)
    else
      logger.warning("Received unknown #{msg['action']} message from player #{player}")
    end
  end

  def handle_draw_message(msg, player)
    @cur_actionables['draw'] = @cur_actionables['draw'] - 1

    case msg['subject']
    when 'deck'
      index_to_draw = @deck.size - 1
      drawn_card = removeCard(index_to_draw, 'deck')
      add_card(drawn_card, 'hand', player)
    when 'discard'
      index_to_draw = @discard.size - 1
      drawn_card = removeCard(index_to_draw, 'discard')
      add_card(drawn_card, 'hand', player)
    end

    return unless @cur_actionables['draw'] == 0

    @actionable_latch.count_down
  end

  def handle_play_message(msg, player)
    @cur_actionables['play'] = @cur_actionables['play'] - msg['index'].size
    indices_to_play = msg['index'].sort { |a, b| b <=> a }

    indices_to_play.each do |i|
      played_card = removeCard(i, 'hand', player)
      @recently_played.append([player, played_card])
      add_card(played_card, 'play_area', player)
    end

    return unless @cur_actionables['play'].zero?

    @actionable_latch.count_down
  end

  def handle_discard_message(msg, player)
    @cur_actionables['discard'] = @cur_actionables['discard'] - msg['index'].size
    indices_to_discard = msg['index'].sort { |a, b| b <=> a }

    indices_to_discard.each do |i|
      discarded_card = removeCard(i, 'hand', player)
      add_card(discarded_card, 'discard')
    end

    return unless @cur_actionables['discard'].zero?

    @actionable_latch.count_down
  end

  def parse_card_list(card_list)
    flat_parsed_cards = parse_cards_flat(card_list)
    hierarchical_parsed_cards = parseCardsHierarchical(card_list)
    { 'flat' => flat_parsed_cards, 'hier' => hierarchical_parsed_cards }
  end

  def parse_cards_flat(list)
    list.flatten.map do |card_string|
      suit, value = card_string.split('_')
      Card.new(suit, value)
    end
  end

  def parseCardsHierarchical(list)
    list.map do |element|
      if element.is_a?(Array)
        parseCardsHierarchical(element)
      else
        suit, value = element.split('_')
        Card.new(suit, value)
      end
    end
  end

  def indicate_deck_visibility(players_to_msg = connected_players())
    msg = {
      "type": 'set_visibility',
      "subject": 'deck',
      "visible": @deck_visibility.to_s
    }
    add_outgoing_message(MessageBuilder.build_info_message(msg), players_to_msg)
  end

  def shuffle_deck
    shuffled_deck = []
    shuffled_deck.append(@deck.delete_at(@rng.rand(@deck.size))) until @deck.empty?
    @deck = shuffled_deck
  end

  def set_starting_discard(discard_instructions) # rubocop:disable Naming/AccessorMethodName
    @discard_visibility = discard_instructions['visible']
    indicate_discard_visibility
  end

  def indicate_discard_visibility(players_to_msg = connected_players())
    msg = {
      "type": 'set_visibility',
      "subject": 'discard',
      "visible": @discard_visibility.to_s
    }
    add_outgoing_message(MessageBuilder.build_info_message(msg), players_to_msg)
  end

  def add_card(card, subject, dir = nil)
    case subject
    when 'deck'
      @deck.append(card)
      add_outgoing_message(MessageBuilder.build_add_card_message(nil, nil, 'deck'))
    when 'discard'
      @discard.append(card)
      add_outgoing_message(MessageBuilder.build_add_card_message(card.suit, card.value, 'discard'))
    when 'hand'
      @hands_rw_lock.with_write_lock do
        @hands[dir].append(card)
      end
      indicate_drawn_card(card, dir, false, true)
    when 'play_area'
      @hands_rw_lock.with_write_lock do
        @play_areas[dir].append(card)
      end
      add_outgoing_message(MessageBuilder.build_add_card_message(card.suit, card.value, 'play_area', dir))
    when 'won_cards'
      @hands_rw_lock.with_write_lock do
        @won_cards[dir].append(card)
      end
      add_outgoing_message(MessageBuilder.build_add_card_message(nil, nil, 'won_cards', dir))
    else
      logger.warn("Tried to add card to unknown subject #{subject}")
    end
  end

  def removeCard(index, subject, dir = nil)
    removed_card = nil

    case subject
    when 'deck'
      removed_card = @deck.delete_at(index)
      add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'deck'))
    when 'discard'
      removed_card = @discard.delete_at(index)
      add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'discard'))
    when 'hand'
      @hands_rw_lock.with_write_lock do
        removed_card = @hands[dir].delete_at(index)
      end
      add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'hand', dir))
    when 'play_area'
      @hands_rw_lock.with_write_lock do
        removed_card = @play_areas[dir].delete_at(index)
      end
      add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'play_area', dir))
    when 'won_cards'
      @hands_rw_lock.with_write_lock do
        removed_card = @won_cards[dir].delete_at(index)
      end
      add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'won_cards', dir))
    else
      logger.warn("Tried to remove card from unknown subject #{subject}")
    end

    removed_card
  end

  def handle_request_place_message(msg, player)
    final_player_dir = player
    unless msg['place'].nil?
      @players_rw_lock.with_write_lock do
        requested_place = msg['place']
        if @players.any? { |player| player == requested_place } && @players['place'].nil?
          final_player_dir = requested_place
          messaging_player_socket = @players[player]
          @players[final_player_dir] = messaging_player_socket
          @players[player] = nil
          # Have to fix the responses, else we'll think they're still in their old seat when they send us messages
          define_websocket_responses(messaging_player_socket, final_player_dir)
          logger.info("Player in slot #{player} was reassigned to slot #{final_player_dir}")
        end
      end
    end
    outgoing_msg = { "type": 'set_player_location', "location": final_player_dir }
    add_outgoing_message(MessageBuilder.build_action_message(outgoing_msg), [final_player_dir])
    indicate_player_connected(final_player_dir)
    inform_state(final_player_dir)
    @players_rw_lock.with_write_lock do
      @players_ready[final_player_dir] = true
    end
  end

  def indicate_player_connected(connected_player_dir, players_to_msg = connected_players())
    outgoing_msg = { "type": 'player_connected', "location": connected_player_dir }
    add_outgoing_message(MessageBuilder.build_action_message(outgoing_msg), players_to_msg)
  end

  def indicate_player_disconnected(disconnected_player_dir)
    outgoing_msg = { "type": 'player_disconnected', "location": disconnected_player_dir }
    add_outgoing_message(MessageBuilder.build_action_message(outgoing_msg), connected_players)
  end

  def get_other_players(dir)
    connected_players.filter { |player| player != dir }
  end

  def inform_state(player_dir)
    logger.info("Reupping state for player in slot #{player_dir}")

    con_players = connected_players
    logger.debug("Reupping connected players state: #{con_players}")
    con_players.each do |dir|
      indicate_player_connected(dir, [player_dir])
    end
    nil unless @game_started
    # TODO: Indicate game state
  end

  def connected_players
    connected_players = nil
    @players_rw_lock.with_read_lock do
      connected_players = @players.reject { |_, value| value.nil? }
    end
    connected_players.keys
  end

  def send_message(msg, receiving_players)
    logger.info("Sending message to #{receiving_players}")
    if !receiving_players.respond_to?('each')
      player = receiving_players
      logger.debug("Sending message to #{player}: #{msg}")
      @players_rw_lock.with_read_lock do
        if !@players[player].nil?
          @players[player].send(msg)
        else
          logger.debug("Couldn't send message to slot #{player} because they weren't connected")
        end
      end
    else
      receiving_players.each do |player|
        logger.debug("Sending message to #{player}: #{msg}")
        @players_rw_lock.with_read_lock do
          if !@players[player].nil?
            @players[player].send(msg)
          else
            logger.debug("Couldn't send message to slot #{player} because they weren't connected")
          end
        end
      end
    end
  end

  def get_next_player(location)
    next_player = location
    viable_player = false
    until viable_player
      next_player = num_to_direction_hash(LOCATION[next_player] + 1)
      viable_player = true if @players.key?(next_player)
    end

    next_player
  end

  def get_previous_player(location)
    last_player = location
    viable_player = false
    until viable_player
      last_player = num_to_direction_hash(LOCATION[last_player] - 1)
      viable_player = true if @players.key?(last_player)
    end

    last_player
  end

  # Step helpers

  # @param step_hash Instructions for the step as a hash (the highest level should always be "step_x" where x is the number of the step)
  def run_step(step_hash) # rubocop:disable Metrics/MethodLength
    logger.debug("Running step: #{step_hash}")
    case step_hash['action']
    when 'setup'
      run_step_setup(step_hash)
    when 'actionable'
      run_step_actionable(step_hash)
    when 'repeat_until'
      run_step_repeat(step_hash)
    when 'assign_trick'
      run_step_assign_trick(step_hash)
    when 'score'
      run_step_score(step_hash)
    when 'assign_winner'
      run_step_winner(step_hash)
    else
      logger.error("Game instructions had an invalid action instruction: #{step_hash['action']}")
    end
  end

  def run_step_setup(step_hash)
    change_prefix = -'change_'
    change_num = 1
    changes_remaining = true
    while changes_remaining
      cur_change = step_hash["#{change_prefix}#{change_num}"]
      if cur_change.nil?
        changes_remaining = false
      else
        case cur_change['action']
        when 'reset_hand'
          @hands.each do |dir, hand|
            removeCard(0, 'hand', dir) until hand.empty?
          end
        when 'shuffle_deck'
          shuffle_deck
        when 'draw'
          num_to_draw = cur_change['amount']
          num_to_draw = @deck.size / @players.size if num_to_draw.nil?
          while num_to_draw.positive?
            @hands.each_key do |hand|
              drawn_card = removeCard(0, 'deck')
              add_card(drawn_card, 'hand', hand)
            end
            num_to_draw -= 1
          end
        end
      end

      change_num += 1
    end

    @cur_step += 1
  end

  def run_step_repeat(step_hash)
    condition_met = checkRepeatCondition(step_hash)

    enact_repeat_change(step_hash['change'])

    if condition_met
      @cur_step += 1
    else
      @cur_step = step_hash['from_step']
    end
  end

  def run_step_actionable(step_hash)
    msg = { 'actionables' => step_hash['actionables'] }

    action_prefix = -'action_'
    actionables = step_hash['actionables']
    cur_action_num = 1
    cur_action = actionables["#{action_prefix}#{cur_action_num}"]
    actions_remaining = true
    while actions_remaining
      @cur_actionables[cur_action['action']] = cur_action['count']
      cur_action_num += 1
      cur_action = actionables["#{action_prefix}#{cur_action_num}"]
      actions_remaining = !cur_action.nil?
    end
    add_outgoing_message(MessageBuilder.build_actionable_message(msg), [@cur_player])

    @actionable_latch = Concurrent::CountDownLatch.new(1)
    @actionable_latch.wait

    @cur_step += 1
  end

  def run_step_assign_trick(_step_hash)
    last_trick = @recently_played.map do |pair|
      pair[1]
    end

    winning_index = @trick_comparator.get_best_card_index(last_trick)
    @last_winner = @recently_played[winning_index][0]
    @play_areas.each do |player, play_area|
      removeCard(0, 'play_area', player) until play_area.empty?
    end
    last_trick.each do |card|
      add_card(card, 'won_cards', @last_winner)
    end
    @recently_played = []

    @cur_step += 1
  end

  def run_step_score(_step_hash)
    logger.warn('UNIMPLEMENTED ACTION TYPE')
    @cur_step += 1
  end

  def run_step_winner(_step_hash)
    logger.warn('UNIMPLEMENTED ACTION TYPE')
    @cur_step += 1
  end

  def checkRepeatCondition(step_hash)
    condition = step_hash['condition']
    comparators = condition['comparators']
    comparison = condition['comparison']
    subject_is_current_player = condition['subject'] == 'cur_player'

    case condition['type']
    when 'occurrences'
      @repeat_incrementers[@cur_step] += 1
      current = @repeat_incrementers[@cur_step]
      compare_bool = compareValues(current, comparison, comparators)
      @repeat_incrementers[@cur_step] = 0 if compare_bool # Need to reset for the next time we get into this loop
      compare_bool
    when 'hand_size'
      if subject_is_current_player
        compareValues(@hands[@cur_player].size, comparison, comparators)
      else
        @hands.values.any? { |hand| compareValues(hand.size, comparison, comparators) }
      end
    when 'score'
      if subject_is_current_player
        compareValues(@players_scores[@cur_player], comparison, comparators)
      else
        @players_scores.values.any? { |score| compareValues(score, comparison, comparators) }
      end
    else
      logger.error("Unknown repeat condition type: #{condition['type']}")
      true
    end
  end

  def compareValues(current, comparison, comparators)
    logger.debug("Checking if #{current} is #{comparators} to #{comparison}")
    comparators.any? do |comparator|
      case comparator
      when 'equal'   then current == comparison
      when 'less'    then current <  comparison
      when 'greater' then current >  comparison
      else
        logger.error("Unknown comparator: #{comparator}")
        true # This will help us move on to further steps to avoid infinite loops
      end
    end
  end

  def enact_repeat_change(change_hash)
    case change_hash['subject']
    when 'player'
      case change_hash['change']
      when 'next'
        @cur_player = get_next_player(@cur_player)
      when 'last_winner'
        @cur_player = @last_winner unless @last_winner.nil?
      else
        logger.error("Unknown player change type: #{change_hash['change']}")
      end
    when 'dealer'
      case change_hash['change']
      when 'next'
        @last_dealer = !@last_dealer.nil? ? get_next_player(@last_dealer) : @cur_player
        @cur_player = get_next_player(@last_dealer)
      else
        logger.error("Unknown dealer change type: #{change_hash['change']}")
      end
    else
      logger.error("Unknown change subject: #{change_hash['subject']}")
    end
  end
end
