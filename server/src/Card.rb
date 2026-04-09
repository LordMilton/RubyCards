class Card
  attr_reader :suit
  attr_reader :value

  # @param suit:String Suit of the card
  # @param value:String Value of the card (string accounts for non-numeral cards)
  def initialize(suit, value)
    @suit = suit
    @value = value
  end
end