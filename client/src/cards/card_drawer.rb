require 'gosu' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment
require_relative 'card'
require_relative '../logger'

# Handles fetching and providing images for Cards
class CardDrawer
  include MyLogger

  HIGHLIGHT_IMAGE_NAME = -'yellow.png'

  def initialize(card_images_dir)
    @card_images_dir = card_images_dir
    @highlight_image = nil

    @card_images = nil
  end

  def initialize_images
    @card_images = {}
    Dir.each_child(@card_images_dir) do |filename|
      full_filename = "#{@card_images_dir}/#{filename}"
      next unless File.extname(full_filename) == '.jpg'

      logger.debug("Fetching card image #{filename} with full path #{full_filename}")
      card_name = filename.sub(/\..+$/, '')
      @card_images[card_name] = Gosu::Image.new(full_filename)
    end
  end

  def card_image(card)
    initialize_images if @card_images.nil?

    if card.hidden?
      @card_images['back']
    else
      @card_images["#{card.suit.downcase}_#{card.value}"]
    end
  end

  def card_hover_text(card, text_height)
    name = card.hidden? ? nil : "#{card.value} of #{card.suit}"
    return Gosu::Image.from_text(name, text_height) unless name.nil?

    nil
  end

  def highlight_image
    card_file = @card_images_dir.dup
    @highlight_image ||= Gosu::Image.new("#{card_file}/../#{HIGHLIGHT_IMAGE_NAME}")
  end
end
