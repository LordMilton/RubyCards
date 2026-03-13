class Hand
  attr_reader :cards

  def initialize
    @cards = []

    # Drawing values
    @topLeftX = nil
    @topLeftY = nil
    @bottomRightX = nil
    @bottomRightY = nil
    @startX = nil
    @cardSpacing = nil
    @cardScaling = nil
  end

  def setHandLocation(topLeftX, topLeftY, bottomRightX, bottomRightY)
    @topLeftX = topLeftX
    @topLeftY = topLeftY
    @bottomRightX = bottomRightX
    @bottomRightY = bottomRightY
    calculateDrawing(topLeftX, topLeftY, bottomRightX, bottomRightY)
  end

  def select(index)
    return @cards[index] || nil
  end

  def add(card)
    calculateDrawingSameLocation
    @cards.append(card)
  end

  def remove(index)
    toReturn = @cards.delete_at(index)
    calculateDrawingSameLocation
    return toReturn
  end

  def draw
    nextX = @startX
    @cards.each do |card|
      card.getImage.draw(nextX, @topLeftY, 0, @cardScaling, @cardScaling)
      nextX += @cardSpacing
    end
  end

  def calculateDrawingSameLocation()
    calculateDrawing(@topLeftX, @topLeftY, @bottomRightX, @bottomRightY)
  end
  private :calculateDrawingSameLocation

  def calculateDrawing(topLeftX, topLeftY, bottomRightX, bottomRightY)
    if(@cards.empty?)
      @startX = 0
      @cardSpacing = 0
      @cardScaling = 0
    else
      sampleCard = @cards[0].getImage

      centerX = (topLeftX + bottomRightX) / 2
      centerY = (topLeftY + bottomRightY) / 2
      handDrawHeight = bottomRightY - topLeftY
      handDrawWidth = bottomRightX - topLeftX
      @cardScaling = handDrawHeight*1.0 / sampleCard.height

      cardWidth = sampleCard.width * @cardScaling
      cardHeight = sampleCard.height * @cardScaling

      if(cardWidth * @cards.length < handDrawWidth)
        @cardSpacing = cardWidth
        @startX = centerX - (cardWidth * @cards.length / 2.0)
      else
        @cardSpacing = handDrawWidth*1.0 / @cards.length
        @startX = topLeftX
      end
    end
  end
  private :calculateDrawing

end