require_relative "../Logger"

class Card
  include MyLogger

  @@HighlightSizePx = 1

  attr_reader :suit
  attr_reader :value
  attr_reader :selected

  # @param suit:String Suit of the card
  # @param value:String Value of the card (string accounts for non-numeral cards)
  # @param cardDrawer:CardDrawer Object for fetching card-related images
  def initialize(suit, value, cardDrawer)
    @suit = suit
    @value = value
    @cardDrawer = cardDrawer
    @selected = false
    @selectable = false

    @topLeftX = 0
    @topLeftY = 0
    @bottomRightX = 0
    @bottomRightY = 0

    @image = nil
  end

  def hidden?
    return(@suit == nil && @value == nil)
  end

  def makeSelectable(selectable)
    @selectable = selectable
  end

  def clicked(clickX, clickY)
    clickWithinBounds = false
    if(pointWithinBounds(clickX, clickY))
      clickWithinBounds = true
      toggleSelected()
    end

    return(clickWithinBounds)
  end

  def pointWithinBounds(x, y)
    return(@topLeftX <= x && @bottomRightX >= x && @topLeftY <= y && @bottomRightY >= y)
  end
  private :pointWithinBounds

  def toggleSelected()
    if(@selectable)
      @selected = !@selected
    end
  end

  def getImage()
    @image ||= @cardDrawer.getCardImage(self)
    return(@image)
  end

  def setDrawingInfo(topLeftX, topLeftY, width, height)
    @topLeftX = topLeftX
    @topLeftY = topLeftY
    @bottomRightX = topLeftX + width
    @bottomRightY = topLeftY + height
  end

  def draw(mouseX, mouseY)
    cardImage = getImage()
    if(cardImage != nil)
      if(@selected)
        drawRectangle(@cardDrawer.getHighlightImage, @topLeftX - @@HighlightSizePx, @topLeftY - @@HighlightSizePx, @bottomRightX + @@HighlightSizePx, @bottomRightY + @@HighlightSizePx)
      end
      drawRectangle(cardImage, @topLeftX, @topLeftY, @bottomRightX, @bottomRightY)
    else
      logger.warning("Tried to draw a card, but its image was null")
      logger.debug("Image for card #{@value} of #{suit} was null")
    end
  end

  def drawRectangle(image, topLeftX, topLeftY, bottomRightX, bottomRightY)
    baseColor = Gosu::Color.argb(0xff_ffffff)
    image.draw_as_quad(
      topLeftX, topLeftY, baseColor,
      bottomRightX, topLeftY, baseColor,
      bottomRightX, bottomRightY, baseColor,
      topLeftX, bottomRightY, baseColor,
      0
    )
  end
  private :drawRectangle

  def getHoverTextDrawer(mouseX, mouseY)
    @hoverText ||= @cardDrawer.getCardHoverText(self, 22)
    if(pointWithinBounds(mouseX, mouseY))
      return proc { @hoverText.draw(mouseX, mouseY + 15, 1) }
    end
    return nil
  end
end