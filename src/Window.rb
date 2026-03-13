require "gosu"
require_relative "cards/Card"
require_relative "cards/CardDrawer"
require_relative "cards/Hand"

class GameWindow < Gosu::Window

  attr_writer :cardDrawer

  def initialize
    super(1920,1080)
    self.resizable = true
    self.caption = "Cards"
    @cardDrawer = CardDrawer.new("../resources/cards")
    @hand = Hand.new()
  end

  def draw
    @hand.setHandLocation(200, 475, 600, 550)
    @hand.draw
  end

  def update
    @hand.add(Card.new("spades", 4, @cardDrawer))
  end

  def close
    self.close!
  end
end

GameWindow.new.show()