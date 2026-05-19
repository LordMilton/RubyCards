require 'gosu' # rubocop:disable Style/FrozenStringLiteralComment,Layout/EndOfLine
require 'json'
require_relative '../cards/card_drawer'
require_relative '../game/game_master'
require_relative '../logger'
require_relative './tcp_socket_client'

class Client
  include MyLogger

  def initialize
    @game_window = nil
    @game_master = nil
    @card_drawer = nil

    @gosu_thread = nil

    @websocket_mtx = Mutex.new
  end

  def run
    @websocket = TcpWebSocketClient.new(
      'localhost',
      25252, # rubocop:disable Style/NumericLiterals
      on_connect: lambda {
        @websocket_mtx.synchronize do
          logger.info('Connected to server')
          @card_drawer = CardDrawer.new('../../resources/cards/')
          @game_master = GameMaster.new(@websocket, @card_drawer)
          @gosu_thread = Thread.new do
            @game_window = GameWindow.new(@game_master)
            logger.info('Starting game window')
            @game_window.show
          end

          msg_hash = { "action": 'request_place' }
          @websocket.send_msg(JSON.generate(msg_hash))
        end
      },
      on_message: lambda { |frame|
        @websocket_mtx.synchronize do
          handle_message(frame)
        end
      },
      on_error: lambda { |err|
        logger.error("Received websocket error: #{err}")
      },
      on_disconnect: lambda {
        logger.debug('Disconnected from server: reason unknown')
        @gosu_thread&.exit
        exit
      }
    )

    @websocket.connect
    @websocket.wait
  end

  private

  def handle_message(frame)
    msg = JSON.parse(frame.to_s)
    logger.debug("Received message: #{msg}")
    case msg['type']
    when 'action'
      msg = msg['msg']
      case msg['type']
      when 'set_player_location'
        @game_master.set_front_player(msg['location'])
      when 'player_connected'
        @game_master.player_connected(msg['location'])
      when 'player_disconnected'
        @game_master.player_disconnected(msg['location'])
      when 'change_score'
        change_score(msg)
      when 'add_card'
        add_card(msg)
      when 'remove_card'
        remove_card(msg)
      else
        logger.warn("Received action message with unknown type #{msg['type']}")
      end
    when 'actionable'
      @game_master.reset_actionables

      actionables = msg['msg']['actionables']
      action_prefix = -'action_'
      cur_action_num = 1
      cur_action = actionables["#{action_prefix}#{cur_action_num}"]
      actions_remaining = true
      while actions_remaining
        logger.info("Adding potential actionable: #{cur_action}")
        @game_master.add_actionable(cur_action['action'], cur_action['count'])

        cur_action_num += 1
        cur_action = actionables["#{action_prefix}#{cur_action_num}"]
        actions_remaining = !cur_action.nil?
      end
    when 'info'
      msg = msg['msg']
      case msg['type']
      when 'set_visibility'
        visible = msg['visible'] == 'true'
        case msg['subject']
        when 'deck'
          @game_master.deck_visible(visible)
        when 'discard'
          @game_master.discard_visible(visible)
        else
          logger.warn("Received set_visibility message with unknown subject #{msg['subject']}")
        end
      else
        logger.warn("Received info message with unknown type #{msg['type']}")
      end
    else
      logger.warn("Received message with an unknown type #{msg['type']}")
    end
  end

  def change_score(msg)
    subject = msg['subject']
    effect = msg['effect']
    value = msg['value']

    case effect
    when 'set'
      @game_master.set_score(subject, value)
    when 'add'
      @game_master.add_to_score(subject, value)
    end
  end

  def add_card(msg)
    card = msg['card']
    suit = card['suit']
    value = card['value']
    new_card = Card.new(suit, value, @card_drawer)

    subject = msg['subject']
    subject_spec = msg['subject_specifier']
    case subject
    when 'deck'
      @game_master.add_to_deck(new_card)
    when 'discard'
      @game_master.add_to_discard(new_card)
    when 'hand'
      @game_master.add_to_hand(subject_spec, new_card)
    when 'play_area'
      @game_master.add_to_play_area(subject_spec, new_card)
    when 'won_cards'
      @game_master.add_to_won_cards(subject_spec, new_card)
    else
      logger.warn("Received add_card message with unknown subject #{msg['subject']}")
    end
  end

  def remove_card(msg)
    index = msg['index']

    subject = msg['subject']
    subject_spec = msg['subject_specifier']
    case subject
    when 'deck'
      @game_master.remove_from_deck(index)
    when 'discard'
      @game_master.remove_from_discard(index)
    when 'hand'
      @game_master.remove_from_hand(subject_spec, index)
    when 'play_area'
      @game_master.remove_from_play_area(subject_spec, index)
    when 'won_cards'
      @game_master.remove_from_won_cards(subject_spec, index)
    else
      logger.warn("Received remove_card message with unknown subject #{msg['subject']}")
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  client = Client.new
  client.run
end
