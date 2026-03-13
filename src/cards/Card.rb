class Card

  attr_reader :suit
  attr_reader :value

  def initialize(suit, value, cardDrawer)
    @suit = suit
    @value = value
    @cardDrawer = cardDrawer
  end

  def hidden?
    return(@suit == nil && @value == nil)
  end

  def getImage
    return(@cardDrawer.getCardImage(self))
  end
end