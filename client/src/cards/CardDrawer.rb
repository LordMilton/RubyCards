require "gosu"
require_relative "Card"

class CardDrawer
  @@HighlightImageName = "yellow.png"
  
  def initialize(cardImagesDir)
    @cardImagesDir = cardImagesDir
    @highlightImage = nil
  end

  def getCardImage(card)
    cardFile = @cardImagesDir.dup
    if(card.hidden?)
      cardFileName = "back.jpg"
    else
      cardFileName = "#{card.suit.downcase}_#{card.value}.jpg"
    end
    
    cardFile = cardFile.concat("/",cardFileName)
    return(Gosu::Image.new(cardFile))
  end

  def getHighlightImage
    cardFile = @cardImagesDir.dup
    if(@highlightImage == nil)
      @highlightImage = Gosu::Image.new("#{cardFile}/../#{@@HighlightImageName}")
    end
    return(@highlightImage)
  end
end