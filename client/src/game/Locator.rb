class Locator
  @@BaseScreenSize = [1920.0,1080.0]

  @@PlayerHandHeight = 150.0
  @@PlayerHandWidth = 400.0
  @@XEdgeBuffer = 50.0
  @@YEdgeBuffer = 50.0

  @@PlayerNameHeightBuffer = 10.0
  @@DesiredPlayerNameHeight = 30.0

  @@DeckHeight = @@PlayerHandHeight
  @@DeckWidth = 75.0

  @@DiscardHeight = @@PlayerHandHeight
  @@DiscardWidth = 350.0

  @@DeckAndDiscardTop = 450.0

  @@ButtonHeight = 40.0
  @@ButtonWidth = 150.0
  @@ButtonHeightBuffer = 10.0
  @@ButtonWidthBuffer = 10.0

  def initialize(screenDimensions)
    calculateInternalDimensions(screenDimensions)
  end

  def calculateInternalDimensions(screenDimensions)
    screenWidth = screenDimensions[0]
    screenHeight = screenDimensions[1]

    @xRatio = @@BaseScreenSize[0] / screenWidth
    @yRatio = @@BaseScreenSize[1] / screenHeight

    @actualHandWidth = @@PlayerHandWidth * @xRatio
    @actualHandHeight = @@PlayerHandHeight * @yRatio

    @actualDeckHeight = @@DeckHeight * @yRatio
    @actualDeckWidth = @@DeckWidth * @xRatio

    @actualDiscardHeight = @@DiscardHeight * @yRatio
    @actualDiscardWidth = @@DiscardWidth * @xRatio

    # X dimensions for hands that are centered on the x axis
    @xCenterLeft = 750 * @xRatio
    @xCenterRight = @xCenterLeft + @actualHandWidth
    # Y dimensions for hands that are centered on the y axis
    @yCenterTop = 450 * @yRatio
    @yCenterBottom = @yCenterTop + @actualHandHeight

    # X buffer from screen edge
    @xBuffer = @@XEdgeBuffer * @xRatio
    # Y buffer from screen edge
    @yBuffer = @@YEdgeBuffer * @yRatio

    # Left hand x dimensions
    @xLefthandLeft = 0 + @xBuffer
    @xLefthandRight = @xLefthandLeft + @actualHandWidth
    # Right hand x dimensions
    @xRighthandRight = screenWidth - @xBuffer
    @xRighthandLeft = @xRighthandRight - @actualHandWidth
    # Top hand y dimensions
    @yTophandTop = 0 + @yBuffer
    @yTophandBottom = @yTophandTop + @actualHandHeight
    # Bottom hand y dimensions
    @yBottomhandBottom = screenHeight - @yBuffer
    @yBottomhandTop = @yBottomhandBottom - @actualHandHeight

    # Player name dimensions
    @actualPlayerNameHeightBuffer = @@PlayerNameHeightBuffer * @yRatio
    @actualDesiredPlayerNameHeight = @@DesiredPlayerNameHeight * @yRatio
    # Bottom player - above the bottom hand
    @bottomNameXCenter = (@xCenterLeft + @xCenterRight) / 2.0
    @bottomNameYCenter = @yBottomhandTop - @actualPlayerNameHeightBuffer - (@actualDesiredPlayerNameHeight / 2)
    # Top player - below the top hand
    @topNameXCenter = (@xCenterLeft + @xCenterRight) / 2.0
    @topNameYCenter = @yTophandBottom + @actualPlayerNameHeightBuffer + (@actualDesiredPlayerNameHeight / 2)
    # Left player - above the left hand
    @leftNameXCenter = (@xLefthandLeft + @xLefthandRight) / 2.0
    @leftNameYCenter = @yCenterTop - @actualPlayerNameHeightBuffer - (@actualDesiredPlayerNameHeight / 2)
    # Right player - above the right hand
    @rightNameXCenter = (@xRighthandLeft + @xRighthandRight) / 2.0
    @rightNameYCenter = @yCenterTop - @actualPlayerNameHeightBuffer - (@actualDesiredPlayerNameHeight / 2)

    # Button dimensions
    @buttonLeftBuffer = @@ButtonWidthBuffer * @xRatio
    @buttonTopBuffer = @@ButtonHeightBuffer * @yRatio
    @buttonLeft = @xCenterRight + @buttonLeftBuffer
    @buttonRight = @buttonLeft + @@ButtonWidth
    @firstButtonTop = @yBottomhandTop

    # Deck dimensions
    @deckLeft = 700 * @xRatio
    @deckRight = @deckLeft + @actualDeckWidth
    @deckTop = @@DeckAndDiscardTop * @yRatio
    @deckBottom = @deckTop + @actualDeckHeight

    # Discard dimensions
    @discardLeft = 850 * @xRatio
    @discardRight = @discardLeft + @actualDiscardWidth
    @discardTop = @@DeckAndDiscardTop * @yRatio
    @discardBottom = @discardTop + @actualDiscardHeight
  end
  private :calculateInternalDimensions

  # names expected to start from bottom player and move clockwise
  def getPlayerHandLocations(players)
    playerHandLocations = [
      [@xCenterLeft,    @yBottomhandTop, @xCenterRight,    @yBottomhandBottom],
      [@xLefthandLeft,  @yCenterTop,     @xLefthandRight,  @yCenterBottom],
      [@xCenterLeft,    @yTophandTop,    @xCenterRight,    @yTophandBottom],
      [@xRighthandLeft, @yCenterTop,     @xRighthandRight, @yCenterBottom]
    ]
    playerHandLocationsHash = {}
    playerHandLocations.zip(players).each do |location, player|
      playerHandLocationsHash[player] = location
    end
    return playerHandLocationsHash
  end

  def getDeckLocation
    return [@deckLeft, @deckTop, @deckRight, @deckBottom]
  end

  def getDiscardLocation
    return [@discardLeft, @discardTop, @discardRight, @discardBottom]
  end

  # first button name will be on top
  def getButtonLocations(buttonNames)
    buttons = {}
    buttonNum = 0
    buttonNames.each do |name|
      thisButtonTop = @firstButtonTop + ((@@ButtonHeight + @@ButtonHeightBuffer) * (buttonNum))
      thisButtonBottom = thisButtonTop + @@ButtonHeight
      buttons[name] = [@buttonLeft, thisButtonTop, @buttonRight, thisButtonBottom]
      buttonNum += 1
    end

    return buttons
  end

  # @param dirNamesHash Player names hashed by their direction. Order should be bottom player first moving clockwise
  # @return Functions which draw the player names provided, hashed in the same way the param was hashed
  def getPlayerNameDrawers(dirNamesHash)
    fontHeight = @actualDesiredPlayerNameHeight.to_i
    #scale = @DesiredPlayerNameHeight / Gosu::Font.new.height
    textDrawers = {}
    textDrawersArray = [
      proc { |name| Gosu::Font.new(fontHeight).draw_text_rel(name, @bottomNameXCenter, @bottomNameYCenter, 1, 0.5, 0.5) },
      proc { |name| Gosu::Font.new(fontHeight).draw_text_rel(name, @leftNameXCenter, @leftNameYCenter, 1, 0.5, 0.5) },
      proc { |name| Gosu::Font.new(fontHeight).draw_text_rel(name, @topNameXCenter, @topNameYCenter, 1, 0.5, 0.5) },
      proc { |name| Gosu::Font.new(fontHeight).draw_text_rel(name, @rightNameXCenter, @rightNameYCenter, 1, 0.5, 0.5) }
    ]
    dirNamesHash.zip(textDrawersArray).each do |dirName, textDrawer|
      key = dirName[0]
      name = dirName[1]
      textDrawers[key] = textDrawer
    end
    return textDrawers
  end
end