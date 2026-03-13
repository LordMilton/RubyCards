require "gosu"
require_relative "Card"

class CardDrawer
  
  def initialize(cardImagesDir)
    @cardImagesDir = cardImagesDir
  end

  def getCardImage(card)
    cardFile = @cardImagesDir.dup
    if(card.hidden?)
      cardFileName = "back.jpg"
    else
      cardFileName = card.suit.downcase.concat("_",card.value.to_s,".jpg")
    end
    
    cardFile = cardFile.concat("/",cardFileName)
    return(Gosu::Image.new(cardFile))
  end
end