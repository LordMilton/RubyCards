require "gosu"
require_relative "cards/Card"
require_relative "cards/CardDrawer"
require_relative "cards/Hand"

class GameWindow < Gosu::Window
  @@LmbId = 256

  attr_writer :cardDrawer

  def initialize
    super(1920,1080)
    self.resizable = true
    self.caption = "Cards"
    @cardDrawer = CardDrawer.new("../resources/cards")
    @hand = Hand.new()
    x = 0
    @hand.setHandLocation(200, 475, 1000, 650)
    while x < 15 do
      @hand.add(Card.new("spades", 4, @cardDrawer))
      x += 1
    end
    @hand.makeSelectable(true)
    @timeNow = Time.new
    @timeLast = Time.new
  end

  def draw
    @hand.draw

    if(@showFps)
      drawFps()
    end
  end

  def drawFps
    @timeLast = @timeNow
    @timeNow = Time.new
    Gosu::Image.from_text(1.0 / (@timeNow - @timeLast) , 20).draw(5,5)
  end
  private :drawFps

  def update
    
  end

  def close
    self.close!
  end

  def button_down(id)
    if(id == @@LmbId)
      @hand.clicked(mouse_x(), mouse_y())
    end
  end
end

GameWindow.new.show()