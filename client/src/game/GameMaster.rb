require 'gosu'
require_relative '../Logger'
require_relative './Button'
require_relative '../cards/Hand'
require_relative './Locator'
require_relative './Window'

LOCATION = {
  'S' => 0,
  'W' => 1,
  'N' => 2,
  'E' => 3
}

DEFAULT_NAMES = {
  'S' => 'South',
  'W' => 'West',
  'N' => 'North',
  'E' => 'East'
}

def numToDirectionHash(num)
  dirs = LOCATION.keys
  dirs[num % dirs.size]
end

class GameMaster
  include MyLogger

  @@BaseScreenSize = [1920, 1080]
  @@PlayerHandHeight = 150
  @@PlayerHandWidth = 400
  @@ButtonHeight = 40
  @@ButtonWidth = 150
  @@ButtonHeightBuffer = 10

  def initialize(websocket, cardDrawer)
    @websocket = websocket
    @cardDrawer = cardDrawer
    @playerPositionsClockwiseFromFront = [numToDirectionHash(0), numToDirectionHash(1), numToDirectionHash(2),
                                          numToDirectionHash(3)]
    # Assumes a 1920,1080 screen, can adjust from there by ratio of new screen sizes
    # TODO: Allow different screen sizes
    @locator = Locator.new(@@BaseScreenSize)

    @playerHandLocations = nil
    @playAreaLocations = nil
    @wonCardsLocations = nil
    setPlayerCardLocations
    @playAreasVisible = true
    @wonCardsVisible = true
    @deckLocation = @locator.getDeckLocation
    createDeck(0)
    @deckVisible = true
    @discardLocation = @locator.getDiscardLocation
    createDiscard
    @discardVisible = true
    @frontPlayer = numToDirectionHash(0)
    @playerHands = {}
    @playAreas = {}
    @wonCards = {}
    @connectedPlayers = []
    @playerNamesDrawers = {}

    @curActionables = {}

    @buttonLabels = %w[Draw Play Discard]
    @buttons = @locator.getButtonLocations(@buttonLabels)
    @buttons.each do |name, location|
      @buttons[name] = Button.new(name.capitalize, location)
    end

    @gameTitleCallback = nil
    @gameName = ''
  end

  def handleFirstFrame
    @cardDrawer.initializeImages
  end

  def createDeck(size)
    @deck = Hand.new('Deck')
    numCards = size
    while numCards > 0
      @deck.add(Card.new(nil, nil, @cardDrawer))
      numCards -= 1
    end
    @deck.setHandLocation(@deckLocation)
  end

  def addToDeck(card)
    @deck.add(card)
  end

  def removeFromDeck(index)
    @deck.remove(0)
  end

  def drawFromDeck(numToDraw = 1)
    @deck.remove(0)
  end

  def makeDeckSelectable(selectable)
    @deck.makeSelectable(selectable)
  end

  def makeDeckVisible(visible)
    @deckVisible = visible
  end

  def createDiscard(cards = Hand.new('Discard'))
    cards.setHandLocation(@discardLocation)
    @discard = cards
  end

  def addToDiscard(card)
    @discard.add(cards)
  end

  def removeFromDiscard(index)
    @discard.remove(index)
  end

  def makeDiscardSelectable(selectable)
    @discard.makeSelectable(selectable)
  end

  def makeDiscardVisible(visible)
    @discardVisible = visible
  end

  def createPlayerHand(hashDir, hand = Hand.new('Hand'))
    if playerSlotExists?(hashDir)
      @playerHands[hashDir] ||= hand
      repositionHands
      return true
    end
    false
  end
  private :createPlayerHand

  def addToHand(hashDir, card)
    if playerSlotExists?(hashDir)
      @playerHands[hashDir].add(card)
      return true
    end
    false
  end

  def removeFromHand(hashDir, index)
    return @playerHands[hashDir].remove(index) if playerSlotExists?(hashDir)

    nil
  end

  def createPlayArea(hashDir, hand = Hand.new('Play Area'))
    if playerSlotExists?(hashDir)
      @playAreas[hashDir] ||= hand
      repositionHands
      return true
    end
    false
  end
  private :createPlayArea

  def makePlayAreasVisible(visible)
    @playAreasVisible = visible
  end

  def addToPlayArea(hashDir, card)
    if playerSlotExists?(hashDir)
      @playAreas[hashDir].add(card)
      return true
    end
    false
  end

  def removeFromPlayArea(hashDir, index)
    return @playAreas[hashDir].remove(index) if playerSlotExists?(hashDir)

    nil
  end

  def createWonCards(hashDir, hand = Hand.new('Cards Won'))
    if playerSlotExists?(hashDir)
      @wonCards[hashDir] ||= hand
      repositionHands
      return true
    end
    false
  end
  private :createWonCards

  def makeWonCardsVisible(visible)
    @wonCardsVisible = visible
  end

  def addToWonCards(hashDir, card)
    if playerSlotExists?(hashDir)
      @wonCards[hashDir].add(card)
      return true
    end
    false
  end

  def removeFromWonCards(hashDir, index)
    return @wonCards[hashDir].remove(index) if playerSlotExists?(hashDir)

    nil
  end

  def addActionable(actionable, count)
    logger.debug("Adding potential actionable: #{actionable}")
    @curActionables[actionable] = count
    if %w[play discard].include?(actionable)
      getFrontPlayerHand.makeSelectable(true)
    elsif actionable == 'draw'
      makeDeckSelectable(true)
    end
  end

  def resetActionables
    @curActionables = {}
    @playerHands.each_value do |hand|
      hand.makeSelectable(false)
    end
    @buttons.each_value do |button|
      button.makeSelectable(false)
    end
    makeDeckSelectable(false)
    makeDiscardSelectable(false)
  end

  # @param callback (String) => nil
  def setGameTitleCallback(callback)
    @gameTitleCallback = callback
    setGameTitle
  end

  def setGameTitle
    return if @gameTitleCallback.nil?

    @gameTitleCallback.call("#{@gameName} (#{DEFAULT_NAMES[@frontPlayer]})")
  end
  private :setGameTitle

  def setPlayerCardLocations
    @playerHandLocations = @locator.getPlayerHandLocations(@playerPositionsClockwiseFromFront)
    @playAreaLocations = @locator.getPlayAreaLocations(@playerPositionsClockwiseFromFront)
    @wonCardsLocations = @locator.getWonCardsLocations(@playerPositionsClockwiseFromFront)
  end
  private :setPlayerCardLocations

  def setFrontPlayer(hashDir)
    logger.debug("Setting position #{hashDir} to be the front player")
    if playerSlotExists?(hashDir)
      difference = (LOCATION[hashDir] - LOCATION[@frontPlayer])
      @playerPositionsClockwiseFromFront.map! { |pos| numToDirectionHash(LOCATION[pos] + difference) }
      setPlayerCardLocations
      @frontPlayer = hashDir
      repositionHands
      setGameTitle
      return true
    end
    false
  end

  def getFrontPlayerHand
    @playerHands[@frontPlayer]
  end

  def repositionHands
    @playerHandLocations.each do |handKey, location|
      hand = @playerHands[handKey]
      hand.setHandLocation(location) unless hand.nil?
    end
    @playAreaLocations.each do |handKey, location|
      playArea = @playAreas[handKey]
      playArea.setHandLocation(location) unless playArea.nil?
    end
    @wonCardsLocations.each do |handKey, location|
      wonCards = @wonCards[handKey]
      wonCards.setHandLocation(location) unless wonCards.nil?
    end
    dirNamesHash = {}
    logger.debug("Connected player slots: #{@connectedPlayers}")
    @playerPositionsClockwiseFromFront.each do |dir|
      dirNamesHash[dir] = @connectedPlayers.include?(dir) ? DEFAULT_NAMES[dir] : ''
    end
    @playerNamesDrawers = @locator.getPlayerNameDrawers(dirNamesHash)
  end
  private :repositionHands

  def playerSlotExists?(hashDir)
    @playerHandLocations.has_key?(hashDir)
  end
  private :playerSlotExists?

  def playerConnected(playerDir)
    logger.debug("Including player slot #{playerDir} in game")
    if !@connectedPlayers.include?(playerDir)
      @connectedPlayers.append(playerDir)
      createPlayerHand(playerDir)
      createPlayArea(playerDir)
      createWonCards(playerDir)
    else
      logger.debug('Ignoring duplicate player connected')
    end
    repositionHands
  end

  def playerDisconnected(playerDir)
    @connectedPlayers.delete(playerDir)
    repositionHands
  end

  def drawGame(mouseX, mouseY)
    # puts('drawing frame')
    @playerHands.each_value do |hand|
      # puts('drawing hand')
      hand.draw(mouseX, mouseY)
    end
    @playerNamesDrawers.each do |dirKey, drawFun|
      # puts('drawing name')
      drawFun.call
    end
    if @playAreasVisible
      @playAreas.each_value do |playArea|
        # puts('drawing play area')
        playArea.draw(mouseX, mouseY)
      end
    end
    if @wonCardsVisible
      @wonCards.each_value do |wonCards|
        # puts('drawing won cards')
        wonCards.draw(mouseX, mouseY)
      end
    end
    if !@deck.nil? && @deckVisible
      # puts('drawing deck')
      @deck.draw(mouseX, mouseY)
    end
    if !@discard.nil? && @discardVisible
      # puts('drawing discard')
      @discard.draw(mouseX, mouseY)
    end
    @buttons.each_value do |btn|
      # puts('drawing button')
      btn.draw(mouseX, mouseY)
    end
  end

  def clicked(mouseX, mouseY)
    cardClicked = false
    @playerHands.values.each do |hand|
      cardClicked ||= hand.clicked(mouseX, mouseY)
    end
    @playAreas.values.each do |hand|
      cardClicked ||= hand.clicked(mouseX, mouseY)
    end
    @wonCards.values.each do |hand|
      cardClicked ||= hand.clicked(mouseX, mouseY)
    end
    cardClicked ||= @deck.clicked(mouseX, mouseY) if @deckVisible
    cardClicked ||= @discard.clicked(mouseX, mouseY) if @discardVisible
    @buttons.each do |actionable, button|
      buttonClicked = button.clicked?(mouseX, mouseY)
      next unless buttonClicked

      msg = { 'action' => actionable }
      if actionable == 'draw'
        msg['subject'] = 'deck'
      else
        msg['subject'] = 'hand'
        msg['index'] = getFrontPlayerHand.getSelectedIndexes
      end
      sendMessage(msg)
      resetActionables
    end

    return unless cardClicked

    enableDisableButtons
  end

  def enableDisableButtons
    # Should assume buttons can't be used unless there's an associated actionable active
    @buttons.each_value do |button|
      button.makeSelectable(false)
    end

    @curActionables.each do |action, count|
      handToCheck = (action == 'draw' ? @deck : getFrontPlayerHand)
      selectedInHandToCheck = handToCheck.getSelected
      @buttons[action].makeSelectable(true) if selectedInHandToCheck.size == count
    end
  end

  def sendMessage(msgHash)
    @websocket.send(JSON.generate(msgHash))
  end
end

if __FILE__ == $0
  sampleCardDrawer = CardDrawer.new('../../resources/cards')
  gm = GameMaster.new(nil, sampleCardDrawer)
  players = %w[S E N W]
  handNum = 2
  players.each do |handKey|
    gm.playerConnected(handKey)
    numCards = 5
    while numCards > 0
      handCard = Card.new(nil, nil, sampleCardDrawer)
      playedCard = Card.new(nil, nil, sampleCardDrawer)
      wonCard = Card.new(nil, nil, sampleCardDrawer)
      gm.addToHand(handKey, handCard)
      gm.addToPlayArea(handKey, playedCard)
      gm.addToWonCards(handKey, wonCard)
      numCards -= 1
    end

    handNum += 1
  end
  # make stuff selectable
  gm.addActionable('play', 1)
  gm.addActionable('draw', 1)

  gm.createDeck(52)
  discard = Hand.new('Discard')
  discardSize = 6
  while discardSize > 0
    discard.add(Card.new('hearts', 'king', sampleCardDrawer))
    discardSize -= 1
  end
  gm.createDiscard(discard)

  gm.makeDiscardVisible(true)
  gm.makeDeckVisible(true)
  gm.makePlayAreasVisible(false)
  gm.makeWonCardsVisible(true)

  window = GameWindow.new(gm).show
end
