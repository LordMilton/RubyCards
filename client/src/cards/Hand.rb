require 'concurrent'
require_relative '../Logger'

class Hand
  include MyLogger

  attr_reader :cards

  BORDER_THICKNESS = 2

  @@HoverTextSize = 22
  @@NameTextSize = 40.0

  def initialize(name)
    @cards = []
    @selectable = false

    @name = name
    @nameImage = nil

    @hoverText = ''
    @hoverTextImage = nil
    @hoverTextRWLock = Concurrent::ReadWriteLock.new

    # Creating any kind of Gosu::Image before the Gosu::Window exists seems to cause a black screen
    # If draw() has been called, we can be confident that Gosu::Window exists
    @drawCalled = false

    # Drawing values
    @leftX = 0
    @topY = 0
    @rightX = 0
    @bottomY = 0
    @startX = 0
    @cardSpacing = 0
    @cardScaling = 0
  end

  # Expected order [leftX, topY, rightX, bottomY]
  def setHandLocation(position)
    if position.respond_to?('each') && position.respond_to?('size') && position.size == 4
      @leftX = position[0]
      @topY = position[1]
      @rightX = position[2]
      @bottomY = position[3]
      calculateDrawing(@leftX, @topY, @rightX, @bottomY)
    else
      puts('setHandLocation given invalid argument: not iterable or not containing 4 elements')
    end
  end

  def makeSelectable(selectable)
    @selectable = selectable
    @cards.each do |card|
      card.makeSelectable(@selectable)
    end
  end

  def getSelected
    @cards.select { |card| card.selected }
  end

  def getSelectedIndexes
    selectedIndexes = []
    @cards.each_index do |index|
      selectedIndexes.append(index) if @cards[index].selected
    end
    selectedIndexes
  end

  def clicked(clickX, clickY)
    clickWithinBounds = false
    if pointWithinBounds(clickX, clickY)
      clickWithinBounds = true
      if @selectable
        @cards.reverse_each do |card|
          break if card.clicked(clickX, clickY)
        end
      end
    end
    clickWithinBounds
  end

  def pointWithinBounds(x, y)
    !@leftX.nil? && @leftX <= x &&
      !@rightX.nil? && @rightX >= x &&
      !@topY.nil? && @topY <= y &&
      !@bottomY.nil? && @bottomY >= y
  end
  private :pointWithinBounds

  def select(index)
    @cards[index] || nil
  end

  def add(card)
    card.makeSelectable(@selectable)
    @cards.append(card)
    calculateDrawingSameLocation
  end

  def remove(index)
    toReturn = @cards.delete_at(index)
    calculateDrawingSameLocation
    toReturn
  end

  def draw(mouseX, mouseY)
    unless @drawCalled
      @drawCalled = true
      fixHoverText
    end

    drawName if @cards.empty?

    hoverTextDrawer = nil
    @cards.each do |card|
      card.draw(mouseX, mouseY)
      newHoverTextDrawer = card.getHoverTextDrawer(mouseX, mouseY)
      hoverTextDrawer = newHoverTextDrawer.nil? ? hoverTextDrawer : newHoverTextDrawer
    end
    if !hoverTextDrawer.nil?
      hoverTextDrawer.call
    elsif pointWithinBounds(mouseX, mouseY)
      drawHoverText(mouseX, mouseY)
    end
    drawBorder
  end

  def drawBorder
    color = Gosu::Color::WHITE
    t = BORDER_THICKNESS
    width = @rightX - @leftX
    height = @bottomY - @topY
    # Top
    Gosu.draw_rect(@leftX - t, @topY - t, width + (2 * t), t, color)
    # Bottom
    Gosu.draw_rect(@leftX - t, @bottomY, width + (2 * t), t, color)
    # Left
    Gosu.draw_rect(@leftX - t, @topY - t, t, height + (2 * t), color)
    # Right
    Gosu.draw_rect(@rightX, @topY - t, t, height + (2 * t), color)
  end
  private :drawBorder

  def drawName
    @nameImage ||= Gosu::Image.from_text(@name, @@NameTextSize)

    # within a^2 + a^2 = c^2
    a = @@NameTextSize / Math.sqrt(2)
    edgeBuffer = 1

    topLeftX = @leftX + a + edgeBuffer
    topLeftY = @topY + edgeBuffer
    topRightX = @rightX - edgeBuffer
    topRightY = @bottomY - a - edgeBuffer
    bottomLeftX = @leftX + edgeBuffer
    bottomLeftY = @topY + a + edgeBuffer
    bottomRightX = @rightX - a - edgeBuffer
    bottomRightY = @bottomY + edgeBuffer

    color = Gosu::Color::WHITE
    @nameImage.draw_as_quad(
      topLeftX,     topLeftY,     color,
      topRightX,    topRightY,    color,
      bottomLeftX,  bottomLeftY,  color,
      bottomRightX, bottomRightY, color,
      0.9
    )
  end
  private :drawName

  def drawHoverText(mouseX, mouseY)
    @hoverTextRWLock.with_write_lock do
      @hoverTextImage ||= Gosu::Image.from_text(@hoverText, @@HoverTextSize)
      return if @hoverTextImage.nil?

      logger.debug("Drawing hover text \"#{@hoverText}\"")
      @hoverTextImage.draw(mouseX, mouseY + 15, 1)
    end
  end
  private :drawHoverText

  def fixHoverText
    @hoverTextRWLock.with_write_lock do
      newHoverText = "#{@cards.size} " + (@cards.size == 1 ? 'Card' : 'Cards')
      return unless @hoverTextImage.nil? || @hoverText != newHoverText

      @hoverText = newHoverText
      logger.debug("Set hover text to be \"#{@hoverText}\"")
      @hoverTextImage = nil
    end
  end
  private :fixHoverText

  def calculateDrawingSameLocation
    calculateDrawing(@leftX, @topY, @rightX, @bottomY)
  end
  private :calculateDrawingSameLocation

  def calculateDrawing(leftX, topY, rightX, bottomY)
    return if leftX.nil? || topY.nil? || rightX.nil? || bottomY.nil?

    fixHoverText
    if @cards.empty?
      @startX = 0
      @cardSpacing = 0
      @cardScaling = 0
    else
      sampleCard = @cards[0].getImage

      centerX = (leftX + rightX) / 2
      centerY = (topY + bottomY) / 2
      handDrawHeight = bottomY - topY
      handDrawWidth = rightX - leftX
      cardScaling = handDrawHeight * 1.0 / sampleCard.height

      @cardWidth = sampleCard.width * cardScaling
      @cardHeight = sampleCard.height * cardScaling
      effectiveHandWidth = handDrawWidth - @cardWidth
      effectiveHandWidth = effectiveHandWidth <= 0 ? 0 : effectiveHandWidth

      if @cardWidth * @cards.size < effectiveHandWidth
        @cardSpacing = @cardWidth
        @startX = centerX - (@cardWidth * @cards.size / 2.0)
      elsif @cards.size == 1
        @cardSpacing = 0
        @startX = leftX
      else
        @cardSpacing = effectiveHandWidth * 1.0 / (@cards.size - 1)
        @startX = leftX
      end

      updateCardLocations
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
