class Card
  attr_reader :suit, :value

  # @param suit:String Suit of the card
  # @param value:String Value of the card (string accounts for non-numeral cards)
  def initialize(suit, value)
    @suit = suit
    @value = value
  end

  def ==(other)
    other.instance_of?(Card) &&
      @suit == other.suit &&
      @value == other.value
  end

  def hash
    [@suit, @value].hash
  end
end
