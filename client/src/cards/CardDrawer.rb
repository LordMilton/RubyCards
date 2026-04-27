require 'gosu'
require_relative 'Card'
require_relative '../Logger'

class CardDrawer
  include MyLogger

  @@HighlightImageName = 'yellow.png'

  def initialize(cardImagesDir)
    @cardImagesDir = cardImagesDir
    @highlightImage = nil

    @cardImages = nil
  end

  def initializeImages
    @cardImages = {}
    Dir.each_child(@cardImagesDir) do |fileName|
      fullFilename = "#{@cardImagesDir}/#{fileName}"
      next unless File.extname(fullFilename) == '.jpg'

      logger.debug("Fetching card image #{fileName} with full path #{fullFilename}")
      cardName = fileName.sub(/\..+$/, '')
      @cardImages[cardName] = Gosu::Image.new(fullFilename)
    end
  end

  def getCardImage(card)
    initializeImages if @cardImages.nil?

    if card.hidden?
      @cardImages['back']
    else
      @cardImages["#{card.suit.downcase}_#{card.value}"]
    end
  end

  def getCardHoverText(card, textHeight)
    name = card.hidden? ? nil : "#{card.value} of #{card.suit}"
    return Gosu::Image.from_text(name, textHeight) unless name.nil?

    nil
  end

  def getHighlightImage
    cardFile = @cardImagesDir.dup
    @highlightImage = Gosu::Image.new("#{cardFile}/../#{@@HighlightImageName}") if @highlightImage.nil?
    @highlightImage
  end
end
