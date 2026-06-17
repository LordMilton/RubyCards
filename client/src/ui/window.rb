require 'concurrent' # rubocop:disable Style/FrozenStringLiteralComment
require 'gosu'
require_relative '../cards/card'
require_relative '../cards/card_drawer'
require_relative '../cards/hand'
require_relative '../logger'

class GameWindow < Gosu::Window
  include MyLogger

  REQUIRED_GUI_METHODS = %i[draw_ui game_title_callback handle_first_frame button_down].freeze

  attr_writer :cardDrawer

  def initialize(graphics_interface)
    return unless duck_verify_graphics_interface(graphics_interface)

    super(1920, 1080)
    self.resizable = false
    self.caption = 'Cards'

    @time_now = Time.new
    @time_last = Time.new
    @frame_in_second = 0

    @first_frame = true
    @show_fps = true

    @new_gui = nil
    @change_gui = false

    change_graphics_interface(graphics_interface)
  end

  def initiate_gui_change(graphics_interface)
    @new_gui = graphics_interface
    @change_gui = true
    logger.debug('gui change requested')
  end

  def change_graphics_interface(graphics_interface)
    logger.debug('changing gui')
    return false unless duck_verify_graphics_interface(graphics_interface)

    @first_frame = true
    @change_caption = false
    @new_caption = ''

    @graphics_interface = graphics_interface
    @graphics_interface.game_title_callback(proc { |title|
      @change_caption = true
      @new_caption = "RubyCards: #{title}"
    })
    @new_gui = nil
    @change_gui = false
  end
  private :change_graphics_interface

  def duck_verify_graphics_interface(graphics_interface)
    missing = REQUIRED_GUI_METHODS.reject { |m| graphics_interface.respond_to?(m) }
    unless missing.empty?
      logger.fatal("graphics_interface is missing required methods: #{missing.join(', ')}")
      return false
    end
    true
  end
  private :duck_verify_graphics_interface

  def draw
    @graphics_interface.draw_ui(self)

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
    change_graphics_interface(@new_gui) if @change_gui

    return unless @first_frame

    @graphics_interface.handle_first_frame
    @first_frame = false
  end

  def close
    exit
  end

  def button_down(id)
    @graphics_interface.button_down(id, self)
  end
end
