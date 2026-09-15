# frozen_string_literal: true

require 'concurrent'
require_relative './card'
require_relative './message_builder'

class HandManager
  include MyLogger
  RESERVED_NAMES = -%w[hand play_area won_cards deck discard]

  def initialize(players, outgoing_msg_q)
    @players = players
    @outgoing_msg_q = outgoing_msg_q
    @hands_rw_lock = Concurrent::ReadWriteLock.new

    @hands = {}
    @play_areas = {}
    @won_cards = {}
    @extra_hands = {}
    @fake_hands = {}
    @deck = []
    @discard = []

    # Visibility: { subject => { dir => bool } }
    # For player-indexed hands, keyed by dir. For others, keyed by subject name.
    # A player not present in the hash defaults to visible (false = hidden)
    @hand_hidden_from = {}

    players.each do |player|
      @hands[player] = []
      @play_areas[player] = []
      @won_cards[player] = []
      init_hidden_tracking('hand', player)
      init_hidden_tracking('play_area', player)
      init_hidden_tracking('won_cards', player)
    end
  end

  # --- Hand creation ---

  def add_extra_hand(name)
    return false unless check_hand_name_valid(name)

    @extra_hands[name] = []
    init_hidden_tracking(name)
  end

  def add_fake_hand(name)
    return false unless check_hand_name_valid(name)

    @fake_hands[name] = []
    # Fake hands are never visible, no tracking needed
  end

  # --- Visibility ---

  def set_hidden_from(subject, viewer_dir, hidden)
    @hand_hidden_from[subject] ||= {}
    @hand_hidden_from[subject][viewer_dir] = hidden
  end

  def hidden_from?(subject, viewer_dir)
    @hand_hidden_from.dig(subject, viewer_dir) || false
  end

  # --- Accessors ---

  attr_reader :hands, :play_areas, :won_cards, :extra_hands, :fake_hands, :deck, :discard

  # --- Card manipulation ---

  def add_card(card, subject, dir = nil)
    with_write_lock do
      case subject
      when 'deck'
        @deck.append(card)
        add_outgoing_message(MessageBuilder.build_add_card_message(nil, nil, 'deck'))
      when 'discard'
        @discard.append(card)
        add_outgoing_message(MessageBuilder.build_add_card_message(card.suit, card.value, 'discard'))
      when 'hand'
        @hands[dir].append(card)
        indicate_added_card_to_hand(card, dir, @players)
      when 'play_area'
        @play_areas[dir].append(card)
        add_outgoing_message(
          MessageBuilder.build_add_card_message(card.suit, card.value, 'play_area', dir)
        )
      when 'won_cards'
        @won_cards[dir].append(card)
        add_outgoing_message(
          MessageBuilder.build_add_card_message(nil, nil, 'won_cards', dir)
        )
      else
        if @extra_hands.include?(subject)
          @extra_hands[subject].append(card)
          add_outgoing_message(
            MessageBuilder.build_add_card_message(card.suit, card.value, subject)
          )
        elsif @fake_hands.include?(subject)
          @fake_hands[subject].append(card)
          # Fake hands are invisible to players, no message sent
        else
          logger.warn("Tried to add card to unknown subject: #{subject}")
        end
      end
    end
  end

  def remove_card(index, subject, dir: nil)
    removed_card = nil

    with_write_lock do
      case subject
      when 'deck'
        removed_card = @deck.delete_at(index)
        add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'deck'))
      when 'discard'
        removed_card = @discard.delete_at(index)
        add_outgoing_message(MessageBuilder.build_remove_card_message(index, 'discard'))
      when 'hand'
        removed_card = @hands[dir].delete_at(index)
        add_outgoing_message(
          MessageBuilder.build_remove_card_message(index, 'hand', dir)
        )
      when 'play_area'
        removed_card = @play_areas[dir].delete_at(index)
        add_outgoing_message(
          MessageBuilder.build_remove_card_message(index, 'play_area', dir)
        )
      when 'won_cards'
        removed_card = @won_cards[dir].delete_at(index)
        add_outgoing_message(
          MessageBuilder.build_remove_card_message(index, 'won_cards', dir)
        )
      else
        if @extra_hands.include?(subject)
          removed_card = @extra_hands[subject].delete_at(index)
          add_outgoing_message(
            MessageBuilder.build_remove_card_message(index, subject)
          )
        elsif @fake_hands.include?(subject)
          removed_card = @fake_hands[subject].delete_at(index)
          # No message for fake hands
        else
          logger.warn("Tried to remove card from unknown subject: #{subject}")
        end
      end
    end

    removed_card
  end

  def shuffle_hand(subject, dir: nil)
    with_write_lock do
      hand = resolve_hand(subject, dir)
      if hand.nil?
        logger.warn("Tried to shuffle unknown subject: #{subject}")
        return
      end

      hand.length.times do
        add_outgoing_message(MessageBuilder.build_remove_card_message(0, subject, dir))
      end

      hand.replace(hand.shuffle)

      hand.each do |card|
        # Deck cards are always indicated without suit/value regardless of visibility
        if subject == 'deck'
          add_outgoing_message(MessageBuilder.build_add_card_message(nil, nil, subject))
        else
          add_outgoing_message(MessageBuilder.build_add_card_message(card.suit, card.value, subject, dir))
        end
      end
    end
  end

  def clear_hand(subject, dir: nil)
    with_write_lock do
      if @fake_hands.include?(subject)
        @fake_hands[subject].clear
        return
      end

      hand = resolve_hand(subject, dir)
      if hand.nil?
        logger.warn("Tried to clear cards from unknown subject: #{subject}")
        return
      end

      hand.length.times do
        add_outgoing_message(MessageBuilder.build_remove_card_message(0, subject, dir))
      end

      until hand.empty?
        @deck.push(hand.pop)
        add_outgoing_message(MessageBuilder.build_add_card_message(nil, nil, 'deck'))
      end
    end
  end

  def with_read_lock(&block)
    @hands_rw_lock.with_read_lock(&block)
  end

  def with_write_lock(&block)
    @hands_rw_lock.with_write_lock(&block)
  end

  private

  def check_hand_name_valid(hand_name)
    return false if RESERVED_NAMES.include?(hand_name) ||
                    @extra_hands.keys.include?(hand_name) ||
                    @fake_hands.keys.include?(hand_name)

    true
  end

  def init_hidden_tracking(subject, dir = nil)
    @hand_hidden_from[subject] ||= {}
    @hand_hidden_from[subject][dir] = false unless dir.nil?
  end

  def resolve_hand(subject, dir)
    case subject
    when 'deck'      then @deck
    when 'discard'   then @discard
    when 'hand'      then @hands[dir]
    when 'play_area' then @play_areas[dir]
    when 'won_cards' then @won_cards[dir]
    else
      @extra_hands[subject] || @fake_hands[subject]
    end
  end

  def indicate_added_card_to_hand(card, owner_dir)
    @players.each do |viewer_dir|
      is_hidden = hidden_from?('hand', viewer_dir)
      suit  = is_hidden ? nil : card.suit
      value = is_hidden ? nil : card.value
      msg = MessageBuilder.build_add_card_message(suit, value, 'hand', owner_dir)
      add_outgoing_message(msg, [viewer_dir])
    end
  end

  def add_outgoing_message(msg, receiving_players = nil)
    @outgoing_msg_q.push([msg, receiving_players])
  end
end
