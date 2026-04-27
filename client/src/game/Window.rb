require 'gosu'
require_relative '../cards/Card'
require_relative '../cards/CardDrawer'
require_relative '../cards/Hand'

class GameWindow < Gosu::Window
  @@LmbId = 256

  attr_writer :cardDrawer

  def initialize(gm)
    super(1920, 1080)
    self.resizable = false
    self.caption = 'Cards'

    @gm = gm
    gm.setGameTitleCallback(proc { |title| self.caption = "RubyCards: #{title}" })

    @timeNow = Time.new
    @timeLast = Time.new
    @frameInSecond = 0

    @firstFrame = true
    @showFps = true
    @playerOrder = %i[S N E W]
    @playerOrderNum = 0
  end

  def draw
    @gm.drawGame(mouse_x, mouse_y)

    return unless @showFps

    drawFps
  end

  def drawFps
    @timeLast = @timeNow
    @timeNow = Time.new
    Gosu::Image.from_text(1.0 / (@timeNow - @timeLast), 20).draw(5, 5)
  end
  private :drawFps

  def update
    return unless @firstFrame

    @gm.handleFirstFrame
    @firstFrame = false
  end

  def close
    close!
  end

  def button_down(id)
    return unless id == @@LmbId

    @gm.clicked(mouse_x, mouse_y)
  end
end
