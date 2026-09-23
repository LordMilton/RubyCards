require 'concurrent' # rubocop:disable Style/FrozenStringLiteralComment
require 'json'
require_relative './card'
require_relative './hand_manager'
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
  # The rest of the parameters are for testing with dependency injection
  # @param players TcpClientConnections keyed by directions. Removes the need to add_players, but the game will still expect
  #                the players to send request_place message to indicate readiness
  # @param player_scores Player scores keyed by directions
  # @param trick_comparator The comparator determining trick winners based on played cards
  # @param starting_deck The list of cards the game should start with. Assuming the game doesn't have instructions to shuffle, this lets you
  #                      set the order of the deck to be what you want
  def initialize(game_file, players: {}, player_scores: {}, trick_comparator: nil, starting_deck: [])
    @rng = Random.new

    # Whether the game is running. It cannot be run twice
    @game_started = false
    # The JSON instruction set retrieved from the game_file
    @instructions = JSON.parse(IO.read("#{GAMES_FOLDER}#{game_file}").gsub(/\r/, ' ').gsub(/\n/, ' '))
    # Separated instruction sets
    @game_instructions = @instructions['game']
    @deck_instructions = @game_instructions['deck']
    @discard_instructions = @game_instructions['discard']
    @scoring_instructions = @game_instructions['scoring']
    # The final instruction step in the game, going beyond it will stop execution of the game
    @final_instruction_step = 0
    # Boolean player readiness keyed by player direction. Only set to true by successful exchange of request_place messages from clients
    @players_ready = {}
    # The list of client websockets keyed by player direction
    @players = players || {}
    # The number of players connected to the game (not the number of _ready_ players)
    @players_count = @players.size
    # Each players' scores keyed by player direction
    @player_scores = player_scores || {}
    # Recent additions to any play areas, beggining is oldest, end is most recent
    # Items are array tuples: [player_direction, card]
    @recently_played = []
    # The initial deck for the game. The cards in this deck are the only cards that will ever be in the game
    @starting_deck = starting_deck
    set_starting_deck(@instructions['game']['deck']) if starting_deck.nil? || starting_deck.empty?
    # The trick comparator object for determining trick winners
    #  Falls back on using the starting_deck as is if something is setting the starting_deck (like a test) but doesn't
    #  set the comparator
    @trick_comparator = trick_comparator || TrickComparator.new(@starting_deck)

    # Data locks
    # Lock when manipulating player websocket connections
    @players_rw_lock = Concurrent::ReadWriteLock.new
    # Lock when manipulating cards in any hand (including deck, discard, extra hands)
    @hands_rw_lock = Concurrent::ReadWriteLock.new

    # Visibility state
    # Whether the deck should be visible on the players' screens
    @deck_visibility = false
    # Whether the discard should be visible on the players' screens
    @discard_visibility = false

    # Special variables for use by the instructions during the game
    # Who last won a trick or round
    @latest_winner = nil
    # The latest _changes_ to scores. e.g. North just got 3 points and has 21 now, this indicates that {N: 3}
    @latest_scores = {}
    # The latest bids
    @latest_bids = {}
    # Whose turn it currently is
    @cur_player = nil
    # Who dealt last
    @latest_dealer = nil
    # The last actionable that was performed by any player (draw/discard/play)
    @latest_actionable = nil

    # Variables for waiting on and handling client actions ("actionables")
    # Lets us block until the current player has actually taken their full turn
    @actionable_latch = nil
    # The actionables currently permitted to be performed by the current player
    @cur_actionables = {}

    # Some variables to avoid having to pass around to/from helper functions
    @cur_step = 1
    # Any incrementers for repeat_untils that are set to happen x number of times. Keyed by step number
    @repeat_incrementers = {}

    # Arbitrary variables created in the ruleset
    @counter_variables = {}
    @flag_variables = {}

    # Message queues
    # TODO mutex?
    @outgoing_msg_q = []

    initialize_game
  end

  # Tries to run the initialized game within this object. Will fail to run if the game isn't full or if this was already run successfully
  def run_game
    all_players_ready = false
    @players_rw_lock.with_read_lock do
      all_players_ready = !@players_ready.value?(false)
    end
    if !all_players_ready
      logger.debug('Not starting game until room is full')
    elsif @game_started
      logger.warn('Something tried to run the game an extra time')
    else
      logger.info('Starting game')

      @game_started = true

      game_complete = false

      presetup(@instructions) # Sets repeatIncrementers and final_instruction_step
      @deck_visibility = @instructions['game']['deck']['visible']
      indicate_deck_visibility
      @starting_deck.each do |card|
        @hand_manager.add_card(card, 'deck')
      end

      set_starting_discard(@instructions['game']['discard'])

      @instructions['game']['extra_hands'].each do |extra_hand|
        unless @hand_manager.add_extra_hand(extra_hand)
          logger.error("Instructions tried to make an extra hand that has a disallowed name '#{extra_hand}'")
        end
      end
      @instructions['game']['fake_hands'].each do |fake_hand|
        unless @hand_manager.add_fake_hand(fake_hand)
          logger.error("Instructions tried to make a fake hand that has a disallowed name '#{fake_hand}'")
        end
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

  # Adds a player to the game, optionally requesting a specific slot
  #
  # @param websocket The websocket connection to the player
  # @param player_dir The requested direction for the player. This also gets handled by request_place, so might be deprecated
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

  # Call to allow sending any stored messages in the outgoing queue. This should be run regularly on a separate thread from the
  #  actual game
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

  # Initializes, but does not start, a game based off the instruction set provided when creating the object
  def initialize_game
    init_instructions = @instructions['game']
    @players_rw_lock.with_write_lock do
      @hands_rw_lock.with_write_lock do
        init_instructions['players'].each do |player|
          @players_ready[player] = false
          @players[player] = nil
          @player_scores[player] = 0
          @cur_player = player
        end
        @seat_placements = SeatPlacements.new(@players.keys)
        @hand_manager = HandManager.new(@players.keys, @outgoing_msg_q)
        @latest_dealer = @seat_placements.last(@cur_player)
      end
    end
  end

  # Does some work before the game starts for things like initializing loop counters
  #
  # @param instructions_hash Entire JSON game intructions
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

  # Builds the initial deck of cards based off the instructions
  #
  # @param deck_instructions JSON intructions for creating the deck
  def set_starting_deck(deck_instructions)
    cards = deck_instructions['cards']
    cards_list = cards['all']
    # card list with no differentiation between trump and fail cards
    if !cards_list.nil?
      cards_parsed = parse_card_list(cards_list)
      @starting_deck = cards_parsed['flat']
      @trick_comparator ||= TrickComparator.new(cards_parsed['hier'])
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

      @trick_comparator ||= TrickComparator.new(trump_hier, fail_cards: fail_hier)

      logger.debug("setting starting deck to #{all_cards}")
      @starting_deck = all_cards.flatten
    end
  end

  # Adds an outgoing message to the queue
  #
  # @param msg The message sent to send to players
  # @param receiving_players The player directions that should receive the message, defaults to all connected players
  def add_outgoing_message(msg, receiving_players = connected_players())
    @outgoing_msg_q.push([msg, receiving_players])
  end

  # Define the callbacks for a websocket
  #
  # @param websocket The websocket whose callbacks we're defining
  # @param player The player direction associated with the websocket
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

  # Handle a message from a player
  #
  # @param msg_json The message sent to the server
  # @param player The player direction that sent the message
  def received_message(msg_json, player)
    msg = JSON.parse(msg_json)
    attempted_action = msg['action']
    if attempted_action.nil?
      logger.warn('Received message with no attempted action, ignoring...')
      return
    end

    # Check that a player isn't trying to play out of turn
    actionables_list = %w[draw play discard]
    if actionables_list.include?(attempted_action) && !@cur_player.nil? && player != @cur_player
      logger.warn("Player in slot #{player} tried to perform #{attempted_action} out of turn! Ignoring...")
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
      logger.warn("Received unknown #{msg['action']} message from player #{player}")
    end
  end

  # Handle a draw message from a player. Contributes to counting down the actionable latch
  #
  # @param msg The message indicating the cards that were drawn
  # @param player The player direction that sent the draw message
  def handle_draw_message(msg, player)
    actionable_name = 'draw'

    return if @cur_actionables[actionable_name].nil? || @cur_actionables[actionable_name] <= 0

    @last_actionable = actionable_name
    @cur_actionables[actionable_name] = @cur_actionables[actionable_name] - 1

    case msg['subject']
    when 'deck'
      index_to_draw = @hand_manager.deck.size - 1
      drawn_card = @hand_manager.remove_card(index_to_draw, 'deck')
      @hand_manager.add_card(drawn_card, 'hand', player)
    when 'discard'
      index_to_draw = @hand_manager.discard.size - 1
      drawn_card = @hand_manager.remove_card(index_to_draw, 'discard')
      @hand_manager.add_card(drawn_card, 'hand', player)
    end

    return unless @cur_actionables[actionable_name].zero?

    @actionable_latch.count_down
  end

  # Handle a play message from a player. Contributes to counting down the actionable latch
  #
  # @param msg The message indicating the cards that were played
  # @param player The player direction that sent the play message
  def handle_play_message(msg, player)
    actionable_name = 'play'

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

  # Handle a discard message from a player. Contributes to counting down the actionable latch
  #
  # @param msg The message indicating the cards that were discarded
  # @param player The player direction that sent the discard message
  def handle_discard_message(msg, player)
    actionable_name = 'discard'

    return if @cur_actionables[actionable_name].nil? || @cur_actionables[actionable_name] <= 0

    @last_actionable = actionable_name
    @cur_actionables[actionable_name] = @cur_actionables[actionable_name] - msg['index'].size
    indices_to_discard = msg['index'].sort { |a, b| b <=> a } # sort in reverse

    indices_to_discard.each do |i|
      discarded_card = remove_card(i, 'hand', dir: player)
      @hand_manager.add_card(discarded_card, 'discard')
    end

    return unless @cur_actionables[actionable_name].zero?

    @actionable_latch.count_down
  end

  # Parse the provided json list of cards
  #
  # @param card_list The json list of cards to parse
  # @return A hash containing the 'flat'tened and 'hier'archical list of cards
  def parse_card_list(card_list)
    flat_parsed_cards = parse_cards_flat(card_list)
    hierarchical_parsed_cards = parse_cards_hierarchical(card_list)
    { 'flat' => flat_parsed_cards, 'hier' => hierarchical_parsed_cards }
  end

  # Parse the provided json list of cards, discarding hierarchy
  #
  # @param list The json list of cards to parse
  # @return The flattened card list
  def parse_cards_flat(list)
    list.flatten.map do |card_string|
      suit, value = card_string.split('_')
      Card.new(suit, value)
    end
  end

  # Parse the provided json list of cards as they are provided, preserving hierarchy
  #
  # @param list The json list of cards to parse
  # @return The hierarchical card list
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

  # Indicate to clients whether the deck needs to be visible (not whether the cards are face up/face down but whether the deck pile
  #  can be seen on the screen at all)
  #
  # @param players_to_msg which player directions to inform about the deck visibility, defaults to all connected players
  def indicate_deck_visibility(players_to_msg = connected_players())
    msg = {
      "type": 'set_visibility',
      "subject": 'deck',
      "visible": @deck_visibility.to_s
    }
    add_outgoing_message(MessageBuilder.build_info_message(msg), players_to_msg)
  end

  # Create the initial discard from the instructions
  #
  # @param discard_instructions The initial discard instructions
  def set_starting_discard(discard_instructions) # rubocop:disable Naming/AccessorMethodName
    @discard_visibility = discard_instructions['visible']
    indicate_discard_visibility
  end

  # Indicate to clients whether the discard needs to be visible (not whether the cards are face up/face down but whether the discard pile
  #  can be seen on the screen at all)
  #
  # @param players_to_msg which player directions to inform about the discard visibility, defaults to all connected players
  def indicate_discard_visibility(players_to_msg = connected_players())
    msg = {
      "type": 'set_visibility',
      "subject": 'discard',
      "visible": @discard_visibility.to_s
    }
    add_outgoing_message(MessageBuilder.build_info_message(msg), players_to_msg)
  end

  # Handles the request place message coming from a client. The server waits for these messages primarily to determine if a client is
  #  actually ready. Can also be used to request a certain directional slot in the game, perhaps for a disconnect/reconnect back into
  #  the same slot
  #
  # @param msg The request_place message sent to the server
  # @param player The direction of the player who sent the message
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

  # Indicate to connected players that a client connected to a player slot
  #
  # @param connected_player_dir The newly connected slot
  # @param players_to_msg Which to players to inform, defaults to all the connected players (includes the newly connected player)
  def indicate_player_connected(connected_player_dir, players_to_msg = connected_players())
    outgoing_msg = { "type": 'player_connected', "location": connected_player_dir }
    add_outgoing_message(MessageBuilder.build_action_message(outgoing_msg), players_to_msg)
  end

  # Indicate to remaining players that a player disconnected from the game
  #
  # @param disconnected_player_dir The disconnected player direction
  def indicate_player_disconnected(disconnected_player_dir)
    outgoing_msg = { "type": 'player_disconnected', "location": disconnected_player_dir }
    add_outgoing_message(MessageBuilder.build_action_message(outgoing_msg), connected_players)
  end

  # Returns a list of all players in the game who aren't the provided player
  #
  # @param dir The player to exclude from the list
  # @return The directions of all players in the game excluding the provided direction
  def get_other_players(dir)
    connected_players.filter { |player| player != dir }
  end

  # Informs the indicated player of all connected players
  # TODO Should inform about more of the game's state, hands, deck, scores, etc.
  #
  # @param player_dir Direction of the player's client to provide the state to
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

  # Returns the list of player directions that have a connected client
  #
  # @return Array of connected directions
  def connected_players
    connected_players = nil
    @players_rw_lock.with_read_lock do
      connected_players = @players.reject { |_, value| value.nil? }
    end
    connected_players.keys
  end

  # Helper for sending messages to clients
  #
  # @param msg Message to send
  # @param receiving_players The list of player directions to send the message to, simply fails for any players not connected
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

  # Step helpers

  # Determine which step needs to run
  #
  # @param step_hash Instructions for the step as a hash
  #   (the highest level should always be "step_x" where x is the number of the step)
  def run_step(step_hash) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/AbcSize
    logger.debug("Running step: #{step_hash}")
    case step_hash['action']
    when 'setup'
      run_step_setup(step_hash)
    when 'cleanup'
      run_step_cleanup(step_hash)
    when 'shuffle'
      run_step_shuffle(step_hash)
    when 'deal'
      run_step_deal(step_hash)
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

  # Run the step to empty hands, usually back into the deck
  #
  # @param step_hash The cleanup instructions
  def run_step_cleanup(step_hash)
    logger.info('Running deal step')
    if check_conditional(step_hash['condition'])
      @hands_rw_lock.with_write_lock do
        hands_to_empty = []

        subject = step_hash['subject']
        subject_specifier =
          if LOCATION.keys.include?(step_hash['subject_specifier'])
            then step_hash['subject_specifier']
          elsif step_hash['subject_specifier'] == 'cur_player'
            then @cur_player
          end
        case subject
        when 'all'
          # Clear player cards
          @players.each_key do |dir|
            hands_to_empty.push(-> { @hand_manager.clear_hand('hand', dir) })
            hands_to_empty.push(-> { @hand_manager.clear_hand('play_area', dir) })
            hands_to_empty.push(-> { @hand_manager.clear_hand('won_cards', dir) })
          end
          # Clear discard
          hands_to_empty.push(lambda {
            @hand_manager.clear_hand('discard')
          })
          # Clear extra hands
          @hand_manager.extra_hands.each_key do |extra_hand_name|
            hands_to_empty.push(lambda {
              @hand_manager.clear_hand(extra_hand_name)
            })
          end
          # Clear fake hands
          @hand_manager.fake_hands.each_key do |fake_hand_name|
            hands_to_empty.push(lambda {
              @hand_manager.clear_hand(fake_hand_name)
            })
          end
        when 'hand', 'play_area', 'won_cards'
          if subject_specifier.nil?
            @players.each_key do |dir|
              hands_to_empty.push(lambda {
                @hand_manager.clear_hand(subject, dir)
              })
            end
          else
            hands_to_empty.push(lambda {
              @hand_manager.clear_hand(subject, subject_specifier)
            })
          end
        when 'discard'
          hands_to_empty.push(lambda {
            @hand_manager.clear_hand(subject)
          })
        else
          if @hand_manager.extra_hands.include?(subject) ||
             @hand_manager.fake_hands.include?(subject)
            hands_to_empty.push(-> { @hand_manager.clear_hand(subject) })
          else
            logger.error("Tried to cleanup unknown cards: #{subject}")
            @cur_step += 1
            return
          end
        end

        hands_to_empty.each(&:call)
      end
    else
      logger.debug('Skipped step due to falsy conditional')
    end

    @cur_step += 1
  end

  # Run the step shuffle any hand in the game
  #
  # @param step_hash The shuffling instructions
  def run_step_shuffle(step_hash)
    logger.info('Running shuffle step')
    if check_conditional(step_hash['condition'])
      @hands_rw_lock.with_write_lock do
        hands_to_shuffle = []

        subject = step_hash['subject']
        subject_specifier =
          if LOCATION.keys.include?(step_hash['subject_specifier'])
            then step_hash['subject_specifier']
          elsif step_hash['subject_specifier'] == 'cur_player'
            then @cur_player
          end
        case subject
        when 'hand', 'play_area', 'won_cards'
          if subject_specifier.nil?
            @players.each_key do |dir|
              hands_to_shuffle.push(
                -> { @hand_manager.shuffle_hand(subject, dir) }
              )
            end
          else
            hands_to_shuffle.push(
              -> { @hand_manager.shuffle_hand(subject, subject_specifier) }
            )
          end
        when 'discard', 'deck'
          hands_to_shuffle.push(-> { @hand_manager.shuffle_hand(subject) })
        else
          if @hand_manager.extra_hands.include?(subject) ||
             @hand_manager.fake_hands.include?(subject)
            hands_to_shuffle.push(-> { @hand_manager.shuffle_hand(subject) })
          else
            logger.error("Tried to cleanup unknown cards: #{subject}")
            @cur_step += 1
            return
          end
        end

        hands_to_shuffle.each(&:call)
      end
    else
      logger.debug('Skipped step due to falsy conditional')
    end

    @cur_step += 1
  end

  # Run the step to deal cards to hands within the game. Any hand in the game should be dealable except for the deck itself
  #
  # @param step_hash The dealing instructions
  def run_step_deal(step_hash)
    logger.info('Running deal step')
    if check_conditional(step_hash['condition'])
      @hands_rw_lock.with_write_lock do
        hands_to_deal = []

        players_sorted = @seat_placements.sort_seats(@players.keys, starting_seat: @seat_placements.next(@dealer))
        subject = step_hash['subject'].nil? ? 'hand' : step_hash['subject']
        subject_specifier =
          if LOCATION.keys.include?(step_hash['subject_specifier'])
            then step_hash['subject_specifier']
          elsif step_hash['subject_specifier'] == 'cur_player'
            then @cur_player
          end
        case subject
        when 'hand', 'play_area', 'won_cards'
          if subject_specifier.nil?
            players_sorted.each do |dir|
              hands_to_deal.push(
                lambda do |card|
                  @hand_manager.add_card(card, subject, dir)
                end
              )
            end
          else
            hands_to_deal.push(
              lambda do |card|
                @hand_manager.add_card(card, subject, subject_specifier)
              end
            )
          end
        when 'discard'
          hands_to_deal.push(
            lambda do |card|
              @hand_manager.add_card(card, subject)
            end
          )
        else
          if @hand_manager.extra_hands.include?(subject) ||
             @hand_manager.fake_hands.include?(subject)
            hands_to_deal.push(
              lambda do |card|
                @hand_manager.add_card(card, subject)
              end
            )
          else
            logger.error("Asked to deal to unknown subject: #{subject}")
          end
        end

        amount = step_hash['amount']
        cards_each = amount.nil? ? ((@hand_manager.deck.length / hands_to_deal.length) + 1) : amount

        cards_each.times do
          break if @hand_manager.deck.empty?

          hands_to_deal.each do |hand|
            break if @hand_manager.deck.empty?

            hand.call(@hand_manager.remove_card(-1, 'deck'))
          end
        end
      end
    else
      logger.debug('Skipped step due to falsy conditional')
    end

    @cur_step += 1
  end

  # Run the step to potentially repeat from an earlier step. Also tends to change a variable like moving the current player to the next player
  #
  # @param step_hash The repetition instructions
  def run_step_repeat(step_hash)
    condition_met = check_conditional(step_hash['condition'])

    change_prefix = 'change_'
    change_num = 1
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

  # Run the step to change the current step to the indicated step. If the conditional isn't met, just goes to the next step like normal steps do
  #
  # @param step_hash The goto instructions
  def run_step_goto(step_hash)
    condition_met = !step_hash.include?('condition') || check_conditional(step_hash['condition'])

    if condition_met
      @cur_step = step_hash['from_step'].to_i
    else
      @cur_step += 1
    end
  end

  # Run the step to change a variable within the game. e.g. setting the current player to the next player or adding 1 to a counter variable
  #
  # @param step_hash The variable changing instructions
  def run_step_change_variable(step_hash)
    condition_met = check_conditional(step_hash['condition'])

    return unless condition_met

    enact_variable_change(step_hash['change'])
  end

  # Run the step to tell players to do something and wait for them to do it.
  #
  # @param step_hash The actionable instructions
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

  # Run the step to assign trick cards to a player. Moves the latest played cards to the trick winner's won cards and increments the step counter
  #
  # @param step_hash The trick winning instructions
  def run_step_assign_trick(_step_hash)
    last_trick = @recently_played.map do |pair|
      pair[1]
    end

    winning_index = @trick_comparator.get_best_card_index(last_trick)
    @latest_winner = @recently_played[winning_index][0]
    @players.each_key do |dir|
      @hand_manager.remove_card(0, 'play_area', dir) until @hand_manager.play_areas[dir].empty?
    end
    last_trick.each do |card|
      @hand_manager.add_card(card, 'won_cards', @latest_winner)
    end
    @recently_played = []

    @cur_step += 1
  end

  # Run the step to score cards. Changes the player scores and increments the step counter
  #
  # @param step_hash The scoring instructions
  def run_step_score(step_hash)
    if check_conditional(step_hash['condition'])
      scores = {}
      @players.each_key do |key|
        scores[key] = 0
      end

      # Determine who should be scored
      players_to_score = []
      @hands_rw_lock.with_read_lock do
        if step_hash['player'].nil?
          players_to_score = @players
        else
          case step_hash['player']
          when 'current'
            players_to_score.push(@cur_player)
          when 'next'
            players_to_score.push(@seat_placements.next(@cur_player))
          when 'last'
            players_to_score.push(@seat_placements.last(@cur_player))
          end
        end

        cards_to_score = {}
        players_to_score.each do |dir|
          cards_to_score[dir] = []
        end

        # Determine what cards should be scored (for each player to be scored)
        subjects = step_hash['subject']
        subjects.each do |subject|
          case subject
          when 'play_area', 'won_cards', 'hand'
            source = case subject
                     when 'play_area' then ->(dir) { @hand_manager.play_areas[dir] }
                     when 'won_cards' then ->(dir) { @hand_manager.won_cards[dir] }
                     when 'hand'      then ->(dir) { @hand_manager.hands[dir] }
                     end
            players_to_score.each do |dir|
              cards_to_score[dir].append(source.call(dir))
            end
          else
            if @hand_manager.extra_hands.include?(subject)
              players_to_score.each do |dir|
                cards_to_score[dir].append(@hand_manager.extra_hands[subject])
              end
            elsif @hand_manager.fake_hands.include?(subject)
              players_to_score.each do |dir|
                cards_to_score[dir].append(@hand_manager.fake_hands[subject])
              end
            else
              logger.warn("Asked to score an unknown set of cards: #{subject}")
            end
          end
        end

        cards_to_score.each do |dir, cards|
          cards_to_score[dir] = cards.flatten
          logger.error("nil cards found in cards_to_score for #{dir}") if cards_to_score[dir].any?(&:nil?)
        end

        # Score cards
        transform_prefix = 'transform_'
        scoring_method = @scoring_instructions[step_hash['method']]
        if scoring_method.include?('card_scores')
          players_to_score.each do |dir|
            next_cards_to_score = cards_to_score[dir]
            scores[dir] = score_cards(next_cards_to_score, scoring_method['card_scores'])
          end
        elsif scoring_method.include?('defined_score')
          players_to_score.each do |dir|
            next_cards_to_score = cards_to_score[dir]
            scores[dir] = score_cards_special(next_cards_to_score, scoring_method['defined_score'])
          end
        end

        # Transform scores if needed
        transform_num = 1
        next_transform = scoring_method["#{transform_prefix}#{transform_num}"]
        until next_transform.nil?
          scores = transform_scores(next_transform, scores)

          transform_num += 1
          next_transform = scoring_method["#{transform_prefix}#{transform_num}"]
        end
      end

      # Apply scores
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

  # Run the step to determine a winner
  #
  # @param step_hash The comparison rules to determine a winner
  # @return The direction of the winning player
  def run_step_winner(_step_hash)
    logger.warn('UNIMPLEMENTED ACTION TYPE')
    @cur_step += 1
  end

  # Score cards based on the rules provided
  #
  # @param cards Cards to score
  # @param scoring_method JSON hash of the points each card scores
  # @return The score for the given cards
  def score_cards(cards, scoring_method)
    scored = cards.map { |card| scoring_method[card.to_s] || 0 }
    scored.sum
  end

  # Score cards based on special, pre-defined rules, anything where the cards score based on the other cards in the list
  #
  # @param cards Cards to score
  # @param scoring_method JSON hash of the special scoring rules
  # @return The score for the given cards
  def score_cards_special(cards, scoring_method)
    if scoring_method.include?('x_of_a_kind')
      score_cards_x_of_a_kind(cards, scoring_method['x_of_a_kind'])
    elsif scoring_method.include?('flush')
      score_cards_flush(cards, scoring_method['flush'])
    elsif scoring_method.include?('straight')
      score_cards_straight(cards, scoring_method['straight'])
    else
      logger.warn("Rules contained an unrecognized special scoring method: #{scoring_method}")
      0
    end
  end

  # Special scoring for straights
  #
  # @param cards Cards to score
  # @param scoring_method JSON hash of flush straight rules, e.g. only score straights of 4 or more cards
  # @return The score for the given cards
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
      scored += (size * scoring_method['score_per_card']) if size >= scoring_method['min_size'].to_i
    end
    scored
  end

  # Special scoring for flushes
  #
  # @param cards Cards to score
  # @param scoring_method JSON hash of flush scoring rules, e.g. only score flushes of 4 or more cards
  # @return The score for the given cards
  def score_cards_flush(cards, scoring_method)
    sets = {}
    cards.each { |card| sets[card.suit] = (sets[card.suit] || 0) + 1 }
    scored = 0
    sets.each_value do |set_size|
      scored += (set_size * scoring_method['score_per_card']) if set_size >= scoring_method['min_size'].to_i
    end
    scored
  end

  # Special scoring for pairs, three of a kinds, etc.
  #
  # @param cards Cards to score
  # @param scoring_method JSON hash of x_of_a_kind scoring rules, e.g. 3 of a kind is worth 6 points
  # @return The score for the given cards
  def score_cards_x_of_a_kind(cards, scoring_method)
    sets = {}
    cards.each { |card| sets[card.value] = (sets[card.value] || 0) + 1 }
    scored = 0
    sets.each_value do |set_size|
      scored += scoring_method[set_size.to_s] || 0
    end
    scored
  end

  # Transforms the provided scores by following the transform_instructions
  #
  # @param transform_instructions JSON hash indicating whether/how to change the given scores
  # @param scores Hash of scores hashed by player directions to be transformed
  # @return The scores post-transformation as a hash. Will include all hashes originally provided in scores
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

  # Checks the conditional provided in the conditional_hash
  #
  # @param conditional_hash All of the instructions contained within "condition"
  # @return True if conditional evaluates to true, False otherwise
  def check_conditional(conditional_hash)
    return true if conditional_hash.nil?

    logger.debug("Checking conditional: #{conditional_hash}")

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
        compare_values(@hand_manager.hands[@cur_player].size, comparison, comparators)
      else
        @hand_manager.hands.values.any? { |hand| compare_values(hand.size, comparison, comparators) }
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

  # Compares provided values based on the provided comparators
  #
  # @param current The current value of something
  # @param comparison What to compare the current value to
  # @param comparators List of comparison words ['equal', 'less', 'greater']. e.g. 'greater' means current > comparison
  def compare_values(current, comparison, comparators)
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

  # Changes a variable within the game based on the json change_hash
  #
  # @param change_hash JSON defining the variable to change and how to change it
  def enact_variable_change(change_hash)
    return if change_hash.nil?

    var_name_to_change = change_hash['subject']
    case var_name_to_change
    when 'player'
      change_cur_player(change_hash)
    when 'dealer'
      change_dealer(change_hash)
    else
      if @counter_variables.include?(var_name_to_change)
        value_change = change_hash['value']
        case change_hash['action']
        when 'set'
          @counter_variables[var_name_to_change] = value_change
        when 'add'
          @counter_variables[var_name_to_change] = @counter_variables[var_name_to_change] + value_change
        else
          logger.error("Unknown counter variable change type: #{change_hash['action']}")
        end
      elsif @flag_variables.include?(var_name_to_change)
        value_change = change_hash['value']
        case change_hash['action']
        when 'set'
          @flag_variables[var_name_to_change] = value_change
        when 'flip'
          @flag_variables[var_name_to_change] = !@flag_variables[var_name_to_change]
        else
          logger.error("Unknown flag variable change type: #{change_hash['action']}")
        end
      else
        logger.error("Unknown variable to change: #{var_name_to_change}")
        true
      end
    end
  end

  # Changes the current player based off the json change_hash
  #
  # @param change_hash JSON Indicating the relative change of the current player
  def change_cur_player(change_hash)
    case change_hash['change']
    when 'next'
      @cur_player = @seat_placements.next(@cur_player)
    when 'last_winner'
      @cur_player = @latest_winner unless @latest_winner.nil?
    else
      logger.error("Unknown player change type: #{change_hash['change']}")
    end
  end

  # Changes the current dealer based off the json change_hash
  #
  # @param change_hash JSON Indicating the relative change of the dealer
  def change_dealer(change_hash)
    case change_hash['change']
    when 'next'
      @latest_dealer = !@latest_dealer.nil? ? @seat_placements.next(@latest_dealer) : @cur_player
      @cur_player = @seat_placements.next(@latest_dealer)
    else
      logger.error("Unknown dealer change type: #{change_hash['change']}")
    end
  end

  # Calculate a player based on another player's position and a string change
  #
  # @param relative_player Player to base the returned player's position off of
  # @param change String indicating the desired relative position of the returned player
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
