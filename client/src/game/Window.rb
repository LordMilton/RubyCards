require "gosu"
require_relative "../cards/Card"
require_relative "../cards/CardDrawer"
require_relative "../cards/Hand"

class GameWindow < Gosu::Window
  @@LmbId = 256

  attr_writer :cardDrawer

  def initialize(gm)
    super(1920,1080)
    self.resizable = true
    self.caption = "Cards"

    @gm = gm

    @timeNow = Time.new
    @timeLast = Time.new
    @frameInSecond = 0
    @playerOrder = [:S, :N, :E, :W]
    @playerOrderNum = 0
  end

  def draw
    @gm.drawGame()

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
    @frameInSecond = (@frameInSecond + 1) % 60
    if(@frameInSecond == 0)
      @gm.setFrontPlayer(@playerOrder[@playerOrderNum % @playerOrder.size])
      @playerOrderNum = (@playerOrderNum + 1) % @playerOrder.size
    end
  end

  def close
    self.close!
  end

  def button_down(id)
    if(id == @@LmbId)
      @gm.clicked(mouse_x(), mouse_y())
    end
  end
end