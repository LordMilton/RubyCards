require_relative "./Card"
require_relative "./Logger"

class TrickComparator
  include MyLogger
  
  def initialize(trumpCards, failCards: nil)
    @trumpCards = trumpCards
    @failCards = failCards == nil ? [] : failCards
    @trumpMinScore = @failCards.size() * 2 + 1
    @ledSuitMinScore = @failCards.size() + 1
  end

  # Cards should be provided in played order to allow determining led suit
  # If the led card is a trump card and there is a tie between other cards, sort order for other cards is unstable
  def sortCards(cards)
    logger.error("UNIMPLEMENTED FUNCTION sortCards")
    return cards
  end

  # Cards should be provided in played order to allow determining led suit
  def getBestCard(cards)
    return cards[getBestCardIndex(cards)]
  end

  # Cards should be provided in played order to allow determining led suit
  def getBestCardIndex(cards)
    ledSuit = cards[0].suit
    bestCardIndex = nil
    bestCardScore = 0
    cards.each_index do |index|
      card = cards[index]
      score = scoreCard(card, ledSuit)
      if(score > bestCardScore)
        bestCardScore = score
        bestCardIndex = index
      elsif(score == bestCardScore)
        logger.warning("Two cards scored equally, trick scoring is going to be non-determinant")
      end
    end
    return bestCardIndex
  end

  def scoreCard(card, ledSuit)
    score = 0
    if(@trumpCards.include?(card))
      score += @trumpMinScore
      score += (@trumpCards.size() - @trumpCards.index(card))
    else
      if(card.suit == ledSuit)
        score += @ledSuitMinScore
      end
      failCardIndex = getFailCardIndex(card)
      if(failCardIndex < 0)
        logger.error("Couldn't find a provided card in the card scorer")
        score = -1
      else
        score += (@failCards.size() - getFailCardIndex(card))
      end
    end
    return score
  end
  private :scoreCard

  def getFailCardIndex(card)
    @failCards.each_index do |index|
      if(@failCards.respond_to?("each") && @failCards[index].include?(card))
        return index
      elsif(!@failCards.respond_to?("each") && @failCards[index] == card)
        return index
      end
    end
    return -1
  end
  private :getFailCardIndex
end