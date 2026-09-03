require 'concurrent' # rubocop:disable Style/FrozenStringLiteralComment,Layout/EndOfLine
require 'json'
require_relative './card'
require_relative './message_builder'
require_relative './logger'
require_relative './seat_placements'
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
    @instructions = JSON.parse(IO.read("#{GAMES_FOLDER}#{game_file}").gsub(/\r/, ' ').gsub(/\n/, ' '))
    @game_instructions = @instructions['game']
    @deck_instructions = @game_instructions['deck']
    @discard_instructions = @game_instructions['discard']
    @scoring_instructions = @game_instructions['scoring']
    @final_instruction_step = 0
    @players_ready = {}
    @players = {}
    @players_count = 0
    @player_scores = {}
    @hands = {}
    @play_areas = {}
    @won_cards = {}
    # Recent additions to any play areas, beggining is oldest, end is most recent
    # Items are array tuples: [player_direction, card]
    @recently_played = []
    @trick_comparator = nil
    @starting_deck = []
    set_starting_deck(@instructions['game']['deck'])
    @deck = []
    @discard = []

    # Extra hands can be made visible and hold actual, non-duplicated cards
    @extra_hands = {}
    # Fake hands will not be visible, and the cards in them are duplicated (when the deck is shuffled, these cards don't matter)
    # They are good for scoring when you need to score combinations of other hands but need to keep those hands separate
    #    for future scoring and such
    @fake_hands = {}

    # Data locks
    @players_rw_lock = Concurrent::ReadWriteLock.new
    @hands_rw_lock = Concurrent::ReadWriteLock.new

    # Visibility state
    @deck_visibility = false
    @discard_visibility = false

    # Special variables for use by the instructions during the game
    @latest_winner = nil
    @latest_scores = {}
    @latest_bids = {}
    @cur_player = nil
    @latest_dealer = nil
    @latest_actionable = nil

    # Variables for waiting on and handling client actions ("actionables")
    @actionable_latch = nil
    @cur_actionables = {}

    # Some variables to avoid having to pass around to/from helper functions
    @cur_step = 1
    @repeat_incrementers = {}

    # Arbitrary variables created in the ruleset
    @counter_variables = {}
    @flag_variables = {}

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

      presetup(@instructions) # Sets repeatIncrementers and final_instruction_step
      @deck_visibility = @instructions['game']['deck']['visible']
      indicate_deck_visibility
      @deck = @starting_deck
      indicate_deck

      set_starting_discard(@instructions['game']['discard'])

      @instructions['extra_hands'].each do |extra_hand|
        @extra_hands[extra_hand] = []
      end
      @instructions['fake_hands'].each do |fake_hand|
        @fake_hands[fake_hand] = []
      end

      until game_complete
        if @cur_step <= @final_instruction_step
          next_step_name = "#{STEP_PREFIX}#{@cur_step}"
          logger.info("Running step \"#{next_step_name}\"")
          run_step(@instructions[next_step_name.to_s])
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
    init_instructions = @instructions['game']
    @players_rw_lock.with_write_lock do
      @hands_rw_lock.with_write_lock do
        init_instructions['players'].each do |player|
          @players_ready[player] = false
          @players[player] = nil
          @player_scores[player] = 0
          @hands[player] = []
          @play_areas[player] = []
          @won_cards[player] = []
          @cur_player = player
          @latest_dealer = get_previous_player(@cur_player)
        end
        @seat_placements = SeatPlacements(@players)
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
    val actionable_name = 'draw'

    return if @cur_actionables[actionable_name].nil? || @cur_actionables[actionable_name] <= 0

    @last_actionable = actionable_name
    @cur_actionables[actionable_name] = @cur_actionables[actionable_name] - 1

    case msg['subject']
    when 'deck'
      index_to_draw = @deck.size - 1
      drawn_card = remove_card(index_to_draw, 'deck')
      add_card(drawn_card, 'hand', player)
    when 'discard'
      index_to_draw = @discard.size - 1
      drawn_card = remove_card(index_to_draw, 'discard')
      add_card(drawn_card, 'hand', player)
    end

    return unless @cur_actionables[actionable_name].zero?

    @actionable_latch.count_down
  end

  def handle_play_message(msg, player)
    val actionable_name = 'play'

    return if @cur_actionables[actionable_name].nil? || @cur_actionables[actionable_name] <= 0

    @last_actionable = actionable_name
    @cur_actionables[actionable_name] = @cur_actionables[actionable_name] - msg['index'].size
    indices_to_play = msg['index'].sort { |a, b| b <=> a }

    indices_to_play.each do |i|
      played_card = remove_card(i, 'hand', dir: player)
      @recently_played.append([player, played_card])
      add_card(played_card, 'play_area', player)
    end

    return unless @cur_actionables[actionable_name].zero?

    @actionable_latch.count_down
  end

  def handle_discard_message(msg, player)
    val actionable_name = 'discard'

    return if @cur_actionables[actionable_name].nil? || @cur_actionables[actionable_name] <= 0

    @last_actionable = actionable_name
    @cur_actionables[actionable_name] = @cur_actionables[actionable_name] - msg['index'].size
    indices_to_discard = msg['index'].sort { |a, b| b <=> a }

    indices_to_discard.each do |i|
      discarded_card = remove_card(i, 'hand', dir: player)
      add_card(discarded_card, actionable_name)
    end

    return unless @cur_actionables[actionable_name].zero?

    @actionable_latch.count_down
  end

  def parse_card_list(card_list)
    flat_parsed_cards = parse_cards_flat(card_list)
    hierarchical_parsed_cards = parse_cards_hierarchical(card_list)
    { 'flat' => flat_parsed_cards, 'hier' => hierarchical_parsed_cards }
  end

  def parse_cards_flat(list)
    list.flatten.map do |card_string|
      suit, value = card_string.split('_')
      Card.new(suit, value)
    end
  end

  def parse_cards_hierarchical(list)
    list.map do |element|
      if element.is_a?(Array)
        parse_cards_hierarchical(element)
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

  def remove_card(index, subject, dir: nil, return_to_deck: false)
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

    return if removed_card.nil?

    add_card(removed_card, 'deck') if return_to_deck

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
    when 'goto'
      run_step_goto(step_hash)
    when 'change_variable'
      run_step_change_variable(step_hash)
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
        when 'reset'
          case cur_change['subject']
          when 'hand'
            @hands.each do |dir, hand|
              remove_card(0, 'hand', dir: dir) until hand.empty?
            end
          when 'won_cards'
            @won_cards.each do |dir, hand|
              remove_card(0, 'won_cards', dir: dir) until hand.empty?
            end
          end
        when 'shuffle_deck'
          shuffle_deck
        when 'deal'
          num_to_draw = cur_change['amount']
          num_to_draw = @deck.size / @players.size if num_to_draw.nil?
          while num_to_draw.positive?
            @hands.each_key do |hand|
              drawn_card = remove_card(0, 'deck')
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

  def run_step_cleanup(step_hash)
    unless check_conditional(step_hash['condition'])
      hands_rw_lock.with_write_lock do
        val hands_to_empty = []

        val subject = step_hash['subject']
        val subject_specifier =
              if LOCATION.keys.include?(step_hash['subject_specifier'])
                then step_hash['subject_specifier']
              elsif step_hash['subject_specifier'] == 'cur_player'
                then @cur_player
              end
        case subject
        when 'all'
          hands.each { |hand| hands_to_empty.push(hand) }
          play_areas.each { |play_area| hands_to_empty.push(play_area) }
          won_cards.each { |won_cards_s| hands_to_empty.push(won_cards_s) }
          hands_to_empty.push(discard)
          extra_hands.each_value { |hand| hands_to_empty.push(hand) }
          fake_hands.each_value { |hand| hand.clear }
        when 'hand'
          if subject_specifier.nil?
            hands.each do |hand|
              hands_to_empty.push(hand)
            end
          else
            hands_to_empty.push(hands[subject_specifier])
          end
        when 'play_area'
          if subject_specifier.nil?
            play_areas.each do |play_area|
              hands_to_empty.push(play_area)
            end
          else
            hands_to_empty.push(play_areas[subject_specifier])
          end
        when 'won_cards'
          if subject_specifier.nil?
            won_cards.each do |won_cards_s|
              hands_to_empty.push(won_cards_s)
            end
          else
            hands_to_empty.push(won_cards[subject_specifier])
          end
        when 'discard'
          hands_to_empty.push(discard)
        else
          if extra_hands.include?(subject)
            hands_to_empty.push(extra_hands[subject])
          elsif fake_hands.include?(subject)
            fake_hands[subject].clear
          else
            logger.error("Tried to cleanup unknown cards: #{subject}")
            @cur_step += 1
            return
          end
        end

        hands_to_empty.each do |hand|
          deck.push(hand.pop) until hand.empty?
        end
      end
    end

    @cur_step += 1
  end

  def run_step_repeat(step_hash)
    condition_met = check_conditional(step_hash['condition'])

    val change_prefix = 'change_'
    var change_num = 1
    while step_hash.include?("#{change_prefix}#{change_num}")
      enact_variable_change(step_hash["#{change_prefix}#{change_num}"])
      change_num += 1
    end

    if condition_met
      @cur_step += 1
    else
      @cur_step = step_hash['from_step']
    end
  end

  def run_step_goto(step_hash)
    condition_met = !step_hash.include?('condition') || check_conditional(step_hash['condition'])

    if condition_met
      @cur_step = step_hash['from_step'].to_i
    else
      @cur_step += 1
    end
  end

  def run_step_change_variable(step_hash)
    val condition_met = check_conditional(step_hash('condition'))

    return unless condition_met

    enact_variable_change(step_hash['change'])
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
    @latest_winner = @recently_played[winning_index][0]
    @play_areas.each do |player, play_area|
      remove_card(0, 'play_area', dir: player) until play_area.empty?
    end
    last_trick.each do |card|
      add_card(card, 'won_cards', @latest_winner)
    end
    @recently_played = []

    @cur_step += 1
  end

  def run_step_score(step_hash)
    if check_conditional(step_hash['condition'])
      scores = {}
      @hands_rw_lock.with_read_lock do
        if step_hash['player'].nil?
          @players.each_key do |key|
            scores[key] = 0
          end
        else
          case step_hash['player']
          when 'current'
            scores[@cur_player] = 0
          when 'next'
            scores[@seat_placements.next(@cur_player)]
          when 'last'
            scores[@seat_placements.last(@cur_player)]
          end
        end

        var player_owned_cards = true # Whether the scoring cards are associated with players, or are generic (like extra_hands)
        cards_to_score = {}
        subject = step_hash['subject']
        case subject
        when 'play_area'
          cards_to_score = @play_areas
        when 'won_cards'
          cards_to_score = @won_cards
        when 'hand'
          cards_to_score = @hands
        else
          player_owned_cards = false
          if @extra_hands.include?(subject)
            cards_to_score = @extra_hands[subject]
          elsif @fake_hands.include?(subject)
            cards_to_score = @fake_hands[subject]
          else
            logger.warning("Tried to score an unknown set of cards: #{subject}")
            @cur_step += 1
            return
          end
        end

        transform_prefix = 'transform_'
        scoring_method = @scoring_instructions[step_hash['method']]
        if scoring_method.include?['card_scores']
          @scores.each_key do |dir|
            val next_cards_to_score = player_owned_cards ? cards_to_score : cards_to_score[dir]
            scores[dir] = score_cards(next_cards_to_score, scoring_method['card_scores'])
          end
        elsif scoring_method.include?['defined_score']
          @scores.each_key do |dir|
            val next_cards_to_score = player_owned_cards ? cards_to_score : cards_to_score[dir]
            scores[dir] = score_cards_special(next_cards_to_score, scoring_method['defined_score'])
          end
        end

        transform_num = 1
        next_transform = scoring_method["#{transform_prefix}#{transform_num}"]
        until next_transform.nil?
          scores = transform_scores(next_transform, scores)

          transform_num += 1
          next_transform = scoring_method["#{transform_prefix}#{transform_num}"]
        end
      end

      @hands_rw_lock.with_write_lock do
        scores.each do |dir, score|
          @player_scores[dir] = score + @player_scores[dir]

          score_msg = { 'type' => 'change_score',
                        'subject' => dir,
                        'effect' => 'add',
                        'value' => score }
          add_outgoing_message(MessageBuilder.build_action_message(score_msg))
        end
      end
    end

    @cur_step += 1
  end

  def run_step_winner(_step_hash)
    logger.warn('UNIMPLEMENTED ACTION TYPE')
    @cur_step += 1
  end

  def score_cards(cards, scoring_method)
    scored = cards.map { |card| scoring_method[card.to_s] || 0 }
    scored.sum
  end

  def score_cards_special(cards, scoring_method)
    if scoring_method.include?('x_of_a_kind')
      score_cards_x_of_a_kind(cards, scoring_method['x_of_a_kind'])
    elsif scoring_method.include?('flush')
      score_cards_x_of_a_kind(cards, scoring_method['flush'])
    elsif scoring_method.include?('straight')
      score_cards_x_of_a_kind(cards, scoring_method['straight'])
    else
      logger.warn("Rules contained an unrecognized special scoring method: #{scoring_method}")
      0
    end
  end

  def score_cards_straight(cards, scoring_method)
    same_suit = scoring_method['same_suit'] || false
    wrap_allowed = false

    value_order = %w[2 3 4 5 6 7 8 9 10 Jack Queen King Ace] # TODO: Ace high or low?

    # Grouping to permit only flush-straights if necessary
    groups =
      if same_suit
        cards.group_by(&:suit).values
      else
        [cards]
      end

    straights = []

    groups.each do |group|
      sorted = group.sort_by { |card| value_order.index(card.value) || 0 }

      used = Array.new(sorted.length, false)

      sorted.each_with_index do |start_card, i|
        next if used[i]

        current_straight = [start_card]
        current_used = [i]
        expected_index = value_order.index(start_card.value) + 1

        loop do
          expected_index %= value_order.length if wrap_allowed

          # Stop if we've wrapped all the way back to the start card
          break if wrap_allowed && expected_index == value_order.index(start_card.value)

          next_index = sorted.index.with_index do |card, j|
            !used[j] && !current_used.include?(j) && value_order.index(card.value) == expected_index
          end

          break unless next_index

          current_straight << sorted[next_index]
          current_used << next_index
          expected_index += 1
        end

        current_used.each { |j| used[j] = true }
        straights << current_straight
      end
    end

    logger.debug("Scoring straights in hand: #{cards}, straights: #{straights} ")

    scored = 0
    straights.each do |straight|
      size = straight.size
      scored += (size * scoringMethod['score_per_card']) if size >= scoringMethod['min_size'].to_i
    end
  end

  def score_cards_flush(cards, scoring_method)
    sets = []
    cards.each { |card| sets[card.suit] = (sets[card.suit] || 0) + 1 }
    scored = 0
    sets.each do |set_size|
      scored += (set_size * scoring_method['score_per_card']) if set_size >= scoring_method['min_size'].to_i
    end
  end

  def score_cards_x_of_a_kind(cards, scoring_method)
    sets = []
    cards.each { |card| sets[card.value] = (sets[card.value] || 0) + 1 }
    scored = 0
    sets.each do |set_size|
      scored += scoring_method[set_size.to_s] || 0
    end
  end

  def transform_scores(transform_instructions, scores)
    condition = transform_instructions['condition']
    comparison = transform_instructions['comparison']
    transformation = transform_instructions['transformation']

    score_additions = {} # Any indication of adding to a player's score
    score_overrides = {} # Any indication of setting a player's score to something else
    should_transform = true
    scores.each do |dir, score|
      unless condition.nil?
        current = nil
        case condition['subject']
        when 'hand_score'
          current = score
        end
        comparison = condition['comparison']
        comparators = condition['comparators']
        should_transform = compare_values(current, comparison, comparators) && should_transform
      end

      #     unless comparison.nil?
      #
      #     end

      next unless should_transform

      current_player_change = transformation['current_player']
      unless current_player_change.nil?
        value = current_player_change['value']
        case current_player_change['action']
        when 'set'
          score_overrides[dir] = value
        when 'add'
          score_additions[dir] = (score_additions[dir] || 0) + value
        end
      end

      other_players_change = transformation['other_players']
      other_players_keys = scores.keys.reject { |override_dir| override_dir == dir }
      next if other_players_change.nil?

      value = other_players_change['value']
      case other_players_change['action']
      when 'set'
        other_players_keys.each do |override_dir|
          score_overrides[override_dir] = value
        end
      when 'add'
        other_players_keys.each do |override_dir|
          score_additions[override_dir] = (score_additions[override_dir] || 0) + value
        end
      end
    end

    scores.each_key do |dir|
      scores[dir] += score_additions[dir] || 0
      scores[dir] = score_overrides[dir] || scores[dir]
    end
    scores
  end

  # @param conditional_hash All of the instructions contained within "condition"
  # @return True if conditional evaluates to true, False otherwise
  def check_conditional(conditional_hash)
    return true if conditional_hash.nil?

    comparators = conditional_hash['comparators']
    comparison = conditional_hash['comparison']
    subject_is_current_player = conditional_hash['subject'] == 'cur_player'

    case conditional_hash['type']
    when 'occurrences'
      @repeat_incrementers[@cur_step] += 1
      current = @repeat_incrementers[@cur_step]
      compare_bool = compare_values(current, comparison, comparators)
      @repeat_incrementers[@cur_step] = 0 if compare_bool # Need to reset for the next time we get into this loop
      compare_bool
    when 'hand_size'
      if subject_is_current_player
        compare_values(@hands[@cur_player].size, comparison, comparators)
      else
        @hands.values.any? { |hand| compare_values(hand.size, comparison, comparators) }
      end
    when 'score'
      if subject_is_current_player
        compare_values(@player_scores[@cur_player], comparison, comparators)
      else
        @player_scores.values.any? { |score| compare_values(score, comparison, comparators) }
      end
    when 'last_actionable'
      @last_actionable == conditional_hash['comparison']
    else
      if @counter_variables.include?(conditional_hash['type'])
        compare_values(@counter_variables[condition['type']], comparison, comparators)
      elsif @flag_variables.include?(conditional_hash['type'])
        @flag_variables[conditional_hash['type']]
      else
        logger.error("Unknown repeat condition type: #{conditional_hash['type']}")
        true
      end
    end
  end

  def compare_values(current, comparison, comparators)
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

  def enact_variable_change(change_hash)
    return if change_hash.nil?

    case change_hash['subject']
    when 'player'
      change_cur_player(change_hash)
    when 'dealer'
      change_dealer(change_hash)
    else
      if counter_variables.include?(var_name_to_change)
        val value_change = change_hash['value']
        case change_hash['action']
        when 'set'
          counter_variables[var_name_to_change] = value_change
        when 'add'
          counter_variables[var_name_to_change] = counter_variables[var_name_to_change] + value_change
        else
          logger.error("Unknown counter variable change type: #{change_hash['action']}")
        end
      elsif flag_variables.include?(var_name_to_change)
        val value_change = change_hash['value']
        case change_hash['action']
        when 'set'
          flag_variables[var_name_to_change] = value_change
        when 'flip'
          flag_variables[var_name_to_change] = !flag_variables[var_name_to_change]
        else
          logger.error("Unknown flag variable change type: #{change_hash['action']}")
        end
      else
        logger.error("Unknown variable to change: #{var_name_to_change}")
        true
      end
    end
  end

  def change_cur_player(change_hash)
    case change_hash['change']
    when 'next'
      @cur_player = seat_placements.next(@cur_player)
    when 'last_winner'
      @cur_player = @latest_winner unless @latest_winner.nil?
    else
      logger.error("Unknown player change type: #{change_hash['change']}")
    end
  end

  def change_dealer(change_hash)
    case change_hash['change']
    when 'next'
      @latest_dealer = !@latest_dealer.nil? ? seat_placements.next(@latest_dealer) : @cur_player
      @cur_player = seat_placements.next(@latest_dealer)
    else
      logger.error("Unknown dealer change type: #{change_hash['change']}")
    end
  end

  def calculate_player(relative_player, change)
    case change
    when 'next'
      @seat_placements.next(relative_player)
    when 'last'
      @seat_placements.last(relative_player)
    when 'dealer'
      @dealer
    when 'left_of_dealer'
      @seat_placements.next(@dealer)
    end
  end
end
