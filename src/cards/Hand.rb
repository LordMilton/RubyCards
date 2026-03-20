class Hand
  attr_reader :cards

  def initialize
    @cards = []
    @selectable = false

    # Drawing values
    @topLeftX = 0
    @topLeftY = 0
    @bottomRightX = 0
    @bottomRightY = 0
    @startX = 0
    @cardSpacing = 0
    @cardScaling = 0
  end

  # Expected order [topLeftX, topLeftY, bottomRightX, bottomRightY]
  def setHandLocation(position)
    if(position.respond_to?("each") && position.respond_to?("size") && position.size == 4)
      @topLeftX = position[0]
      @topLeftY = position[1]
      @bottomRightX = position[2]
      @bottomRightY = position[3]
      calculateDrawing(@topLeftX, @topLeftY, @bottomRightX, @bottomRightY)
    else
      puts("Hand.setHandLocation given invalid argument: not iterable or not containing 4 elements")
    end
  end

  def makeSelectable(selectable)
    @selectable = selectable
    @cards.each do |card|
      card.makeSelectable(@selectable)
    end
  end

  def clicked(clickX, clickY)
    clickWithinBounds = false
    if(pointWithinBounds(clickX, clickY))
      clickWithinBounds = true
      if(@selectable)
        @cards.reverse_each do |card|
          if(card.clicked(clickX, clickY))
            break
          end
        end
      end
    end
    return(clickWithinBounds)
  end

  def pointWithinBounds(x, y)
    return(
      (@topLeftX != nil && @topLeftX <= x) &&
      (@bottomRightX != nil && @bottomRightX >= x) &&
      (@topLeftY != nil && @topLeftY <= y) &&
      (@bottomRightY != nil && @bottomRightY >= y)
    )
  end
  private :pointWithinBounds

  def select(index)
    return @cards[index] || nil
  end

  def add(card)
    card.makeSelectable(@selectable)
    @cards.append(card)
    calculateDrawingSameLocation()
  end

  def remove(index)
    toReturn = @cards.delete_at(index)
    calculateDrawingSameLocation()
    return toReturn
  end

  def draw
    @cards.each do |card|
      card.draw
    end
  end

  def calculateDrawingSameLocation()
    calculateDrawing(@topLeftX, @topLeftY, @bottomRightX, @bottomRightY)
  end
  private :calculateDrawingSameLocation

  def calculateDrawing(topLeftX, topLeftY, bottomRightX, bottomRightY)
    if(topLeftX == nil || topLeftY == nil || bottomRightX == nil || bottomRightY == nil)
      return
    end

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
      cardScaling = handDrawHeight*1.0 / sampleCard.height

      @cardWidth = sampleCard.width * cardScaling
      @cardHeight = sampleCard.height * cardScaling

      if(@cardWidth * @cards.size < handDrawWidth)
        @cardSpacing = @cardWidth
        @startX = centerX - (@cardWidth * @cards.size / 2.0)
      else
        @cardSpacing = handDrawWidth*1.0 / @cards.size
        @startX = topLeftX
      end

      updateCardLocations()
    end
  end
  private :calculateDrawing

  def updateCardLocations
    nextX = @startX
    @cards.each do |card|
      card.setDrawingInfo(nextX, @topLeftY, @cardWidth, @cardHeight)
      nextX += @cardSpacing
    end
  end

end