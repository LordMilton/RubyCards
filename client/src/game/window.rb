require 'gosu' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative '../cards/card'
require_relative '../cards/card_drawer'
require_relative '../cards/hand'
require_relative '../logger'

class GameWindow < Gosu::Window
  include MyLogger

  @@LmbId = 256

  attr_writer :cardDrawer

  def initialize(game_master)
    super(1920, 1080)
    self.resizable = false
    self.caption = 'Cards'

    @change_caption = false
    @new_caption = ''

    @game_master = game_master
    @game_master.game_title_callback(proc { |title|
      @change_caption = true
      @new_caption = "RubyCards: #{title}"
    })

    @time_now = Time.new
    @time_last = Time.new
    @frame_in_second = 0

    @first_frame = true
    @show_fps = true
  end

  def draw
    @game_master.draw_game(mouse_x, mouse_y)

    return unless @show_fps

    draw_fps
  end

  def draw_fps
    @time_last = @time_now
    @time_now = Time.new
    Gosu::Image.from_text(1.0 / (@time_now - @time_last), 20).draw(5, 5)
  end
  private :draw_fps

  def update
    self.caption = @new_caption if @change_caption

    return unless @first_frame

    @game_master.handle_first_frame
    @first_frame = false
  end

  def close
    exit
  end

  def button_down(id)
    return unless id == @@LmbId

    @game_master.clicked(mouse_x, mouse_y)
  end
end
