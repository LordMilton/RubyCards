require "gosu"
require_relative "../Logger"
require_relative "./Button"
require_relative "../cards/Hand"
require_relative "./Locator"
require_relative "./Window"

LOCATION = {
  "S" => 0,
  "W" => 1,
  "N" => 2,
  "E" => 3
}

DEFAULT_NAMES = {
  "S" => "South",
  "W" => "West",
  "N" => "North",
  "E" => "East"
}

def numToDirectionHash(num)
  dirs = LOCATION.keys
  return dirs[num % dirs.size]
end

class GameMaster
  include MyLogger

  @@BaseScreenSize = [1920,1080]
  @@PlayerHandHeight = 150
  @@PlayerHandWidth = 400
  @@ButtonHeight = 40
  @@ButtonWidth = 150
  @@ButtonHeightBuffer = 10

  def initialize(websocket, cardDrawer)
    @websocket = websocket
    @cardDrawer = cardDrawer
    @playerPositionsClockwiseFromFront = [numToDirectionHash(0), numToDirectionHash(1), numToDirectionHash(2), numToDirectionHash(3)]
    # Assumes a 1920,1080 screen, can adjust from there by ratio of new screen sizes
    # TODO: Allow different screen sizes
    @locator = Locator.new(@@BaseScreenSize)

    @playerHandLocations = @locator.getPlayerHandLocations(@playerPositionsClockwiseFromFront)
    @deckLocation = @locator.getDeckLocation
    createDeck(0)
    @deckVisible = true
    @discardLocation = @locator.getDiscardLocation
    createDiscard()
    @discardVisible = true
    @frontPlayer = numToDirectionHash(0)
    @playerHands = {}
    @connectedPlayers = []
    @playerNamesDrawers = {}

    @buttonLabels = ["Draw", "Play", "Discard"]
    @buttons = @locator.getButtonLocations(@buttonLabels)
    @buttons.each do |name, location|
      @buttons[name] = Button.new(name, location)
    end
  end

  def createDeck(size)
    @deck = Hand.new
    numCards = size
    while numCards > 0 do
      @deck.add(Card.new(nil, nil, @cardDrawer))
      numCards -= 1
    end
    @deck.setHandLocation(@deckLocation)
  end

  def addToDeck(card)
    @deck.add(card)
  end

  def removeFromDeck(index)
    return @deck.remove(0)
  end

  def drawFromDeck(numToDraw = 1)
    return @deck.remove(0)
  end

  def makeDeckSelectable(selectable)
    @deck.makeSelectable(selectable)
  end

  def makeDeckVisible(visible)
    @deckVisibility = visible
  end

  def createDiscard(cards = Hand.new)
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
    @discardVisibility = visible
  end

  def createPlayerHand(hashDir, hand = Hand.new)
    if(playerSlotExists?(hashDir))
      @playerHands[hashDir] ||= hand
      repositionHands()
      return true
    end
    return false
  end

  def addToHand(hashDir, card)
    if(playerSlotExists?(hashDir))
      @playerHands[hashDir].add(card)
      return true
    end
    return false
  end

  def removeFromHand(hashDir, index)
    if(playerSlotExists?(hashDir))
      @playerHands[hashDir].add(card)
      return true
    end
    return false
  end

  def setFrontPlayer(hashDir)
    logger.debug("Setting position #{hashDir} to be the front player")
    if(playerSlotExists?(hashDir))
      difference = (LOCATION[hashDir] - LOCATION[@frontPlayer])
      @playerPositionsClockwiseFromFront.map! { |pos| numToDirectionHash(LOCATION[pos] + difference) }
      @playerHandLocations = @locator.getPlayerHandLocations(@playerPositionsClockwiseFromFront)
      @frontPlayer = hashDir
      repositionHands()
      return true
    end
    return false
  end

  def repositionHands
    @playerHandLocations.each do |handKey, location|
      hand = @playerHands[handKey]
      if(hand != nil)
        hand.setHandLocation(location)
      end
    end
    dirNamesHash = {}
    logger.debug("Connected player slots: #{@connectedPlayers}")
    @playerPositionsClockwiseFromFront.each do |dir|
      dirNamesHash[dir] = (@connectedPlayers.include?(dir)) ? DEFAULT_NAMES[dir] : ""
    end
    puts("Moving/assigning player names drawers: #{dirNamesHash}")
    @playerNamesDrawers = @locator.getPlayerNameDrawers(dirNamesHash)
  end
  private :repositionHands

  def playerSlotExists?(hashDir)
    return @playerHandLocations.has_key?(hashDir)
  end
  private :playerSlotExists?

  def playerConnected(playerDir)
    logger.debug("Including player slot #{playerDir} in game")
    if(!@connectedPlayers.include?(playerDir))
      @connectedPlayers.append(playerDir)
      createPlayerHand(playerDir)
    else
      logger.debug("Ignoring duplicate player connected")
    end
    repositionHands()
  end

  def playerDisconnected(playerDir)
    @connectedPlayers.delete(playerDir)
    repositionHands()
  end

  def drawGame(mouseX, mouseY)
    @playerHands.each_value do |hand|
      hand.draw
    end
    @playerNamesDrawers.each do |dirKey, drawFun|
      drawFun.call()
    end
    if(@deck != nil && @deckVisible)
      @deck.draw
    end
    if(@discard != nil && @discardVisible)
      @discard.draw
    end
    @buttons.each_value do |btn|
      btn.draw(mouseX, mouseY)
    end
  end

  def clicked(mouseX, mouseY)
    @playerHands.values.each do |hand|
      hand.clicked(mouseX, mouseY)
    end
    if(@deckVisible)
      @deck.clicked(mouseX, mouseY)
    end
    if(@discardVisible)
      @discard.clicked(mouseX, mouseY)
    end
  end

end

if __FILE__ == $0
  sampleCardDrawer = CardDrawer.new("../../resources/cards")
  gm = GameMaster.new(sampleCardDrawer)
  sampleHands = {S: nil}
  handNum = 2
  sampleHands.each do |handKey, hand|
    numCards = 10
    newHand = Hand.new()
    newHand.makeSelectable(true)
    while numCards > 0 do
      newHand.add(Card.new("spades", handNum, sampleCardDrawer))
      numCards -= 1
    end
    sampleHands[handKey] = newHand
    gm.createPlayerHand(handKey, newHand)
    handNum += 1
  end

  gm.createDeck(52)
  discard = Hand.new
  discardSize = 6
  while discardSize > 0 do
    discard.add(Card.new("hearts", 8, sampleCardDrawer))
    discardSize -= 1
  end
  gm.createDiscard(discard)

  window = GameWindow.new(gm).show()
end