require_relative './card' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative './logger'

# Class for comparing cards within a trick based on provided trump and fail card lists
class TrickComparator
  include MyLogger

  def initialize(trump_cards, fail_cards: nil)
    @trump_cards = trump_cards
    @fail_cards = fail_cards.nil? ? [] : fail_cards
    @trump_min_score = @fail_cards.size * 2 + 1
    @led_suit_min_score = @fail_cards.size + 1
  end

  # Cards should be provided in played order to allow determining led suit
  # If the led card is a trump card and there is a tie between other cards, sort order for other cards is unstable
  def sort_cards(cards)
    logger.error('UNIMPLEMENTED FUNCTION sort_cards')
    cards
  end

  # Cards should be provided in played order to allow determining led suit
  def get_best_card(cards)
    cards[get_best_card_index(cards)]
  end

  # Cards should be provided in played order to allow determining led suit
  def get_best_card_index(cards)
    led_suit = cards[0].suit
    best_card_index = nil
    best_card_score = 0
    cards.each_index do |index|
      card = cards[index]
      score = score_card(card, led_suit)
      if score > best_card_score
        best_card_score = score
        best_card_index = index
      elsif score == best_card_score
        logger.warning('Two cards scored equally, trick scoring is going to be non-determinant')
      end
    end
    best_card_index
  end

  private

  def score_card(card, led_suit)
    score = 0
    if @trump_cards.include?(card)
      score += @trump_min_score
      score += (@trump_cards.size - @trump_cards.index(card))
    else
      score += @led_suit_min_score if card.suit == led_suit
      fail_card_index = get_fail_card_index(card)
      if fail_card_index.negative?
        logger.error("Couldn't find a provided card in the card scorer")
        score = -1
      else
        score += (@fail_cards.size - get_fail_card_index(card))
      end
    end
    score
  end

  def get_fail_card_index(card)
    @fail_cards.each_index do |index|
      if @fail_cards.respond_to?('each') && @fail_cards[index].include?(card)
        return index
      elsif !@fail_cards.respond_to?('each') && @fail_cards[index] == card
        return index
      end
    end
    -1
  end
end
