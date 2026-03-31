class Hand
  attr_reader :cards

  def initialize
    @cards = []
    @selectable = false

    # Drawing values
    @leftX = 0
    @topY = 0
    @rightX = 0
    @rightY = 0
    @startX = 0
    @cardSpacing = 0
    @cardScaling = 0
  end

  # Expected order [leftX, topY, rightX, rightY]
  def setHandLocation(position)
    if(position.respond_to?("each") && position.respond_to?("size") && position.size == 4)
      @leftX = position[0]
      @topY = position[1]
      @rightX = position[2]
      @rightY = position[3]
      calculateDrawing(@leftX, @topY, @rightX, @rightY)
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

  def getSelected()
    return(@cards.select { |card| card.selected} )
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
      (@leftX != nil && @leftX <= x) &&
      (@rightX != nil && @rightX >= x) &&
      (@topY != nil && @topY <= y) &&
      (@rightY != nil && @rightY >= y)
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
    calculateDrawing(@leftX, @topY, @rightX, @rightY)
  end
  private :calculateDrawingSameLocation

  def calculateDrawing(leftX, topY, rightX, rightY)
    if(leftX == nil || topY == nil || rightX == nil || rightY == nil)
      return
    end

    if(@cards.empty?)
      @startX = 0
      @cardSpacing = 0
      @cardScaling = 0
    else
      sampleCard = @cards[0].getImage

      centerX = (leftX + rightX) / 2
      centerY = (topY + rightY) / 2
      handDrawHeight = rightY - topY
      handDrawWidth = rightX - leftX
      cardScaling = handDrawHeight*1.0 / sampleCard.height

      @cardWidth = sampleCard.width * cardScaling
      @cardHeight = sampleCard.height * cardScaling
      effectiveHandWidth = handDrawWidth - @cardWidth
      effectiveHandWidth = effectiveHandWidth <= 0 ? 0 : effectiveHandWidth

      if(@cardWidth * @cards.size < effectiveHandWidth)
        @cardSpacing = @cardWidth
        @startX = centerX - (@cardWidth * @cards.size / 2.0)
      else
        @cardSpacing = effectiveHandWidth*1.0 / @cards.size
        @startX = leftX
      end

      updateCardLocations()
    end
  end
  private :calculateDrawing

  def updateCardLocations
    nextX = @startX
    @cards.each do |card|
      card.setDrawingInfo(nextX, @topY, @cardWidth, @cardHeight)
      nextX += @cardSpacing
    end
  end

end