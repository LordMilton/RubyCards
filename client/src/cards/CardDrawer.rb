require "gosu"
require_relative "Card"

class CardDrawer
  @@HighlightImageName = "yellow.png"
  
  def initialize(cardImagesDir)
    @cardImagesDir = cardImagesDir
    @highlightImage = nil

    @cardImages = nil
  end

  def initializeImages()
    @cardImages = {}
    Dir.each_child(@cardImagesDir) { |fileName|
      fullFilename = "#{@cardImagesDir}/#{fileName}"
      if(File.extname(fullFilename) == ".jpg")
        puts("Fetching card image #{fileName} with full path #{fullFilename}")
        cardName = fileName.sub(/\..+$/, "")
        @cardImages[cardName] = Gosu::Image.new(fullFilename)
      end
    }
  end

  def getCardImage(card)
    if(@cardImages == nil)
      initializeImages()
    end
    
    cardImage = nil
    if(card.hidden?)
      cardImage = @cardImages["back"]
    else
      cardImage = @cardImages["#{card.suit.downcase}_#{card.value}"]
    end
    return(cardImage)
  end

  def getCardHoverText(card, textHeight)
    name = ""
    if(!card.hidden?)
      name = "#{card.value} of #{card.suit}"
    end
    return(Gosu::Image.from_text(name, textHeight))
  end

  def getHighlightImage
    cardFile = @cardImagesDir.dup
    if(@highlightImage == nil)
      @highlightImage = Gosu::Image.new("#{cardFile}/../#{@@HighlightImageName}")
    end
    return(@highlightImage)
  end
end