require "gosu"
require_relative "../cards/Hand"
require_relative "./Window.rb"

LOCATION = {
  S: 0,
  W: 1,
  N: 2,
  E: 3
}

def numToDirectionHash(num)
  dirs = LOCATION.keys
  return dirs[num % dirs.size]
end

class GameMaster
  @@BaseScreenSize = [1920,1080]
  @@PlayerHandHeight = 150
  @@PlayerHandWidth = 350

  def initialize(cardDrawer)
    @cardDrawer = cardDrawer
    # Assumes a 1920,1080 screen, can adjust from there by ratio of new screen sizes
    # TODO: Allow different screen sizes
    @playerHandLocations = {
      numToDirectionHash(0) => [750,                    1020-@@PlayerHandHeight, 750+@@PlayerHandWidth, 1020],
      numToDirectionHash(1) => [50,                     450,                     50+@@PlayerHandWidth,  450+@@PlayerHandHeight],
      numToDirectionHash(2) => [750,                    50,                      750+@@PlayerHandWidth, 50+@@PlayerHandHeight],
      numToDirectionHash(3) => [1800-@@PlayerHandWidth, 450,                     1800,                  450+@@PlayerHandHeight]
    }
    @deckLocation = [700, 450, 710, 450+@@PlayerHandHeight]
    @discardLocation = [850, 450, 1000, 450+@@PlayerHandHeight]
    @frontPlayer = numToDirectionHash(0)
    @playerHands = {}
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

  def drawFromDeck(numToDraw = 1)
    return @deck.remove(0)
  end

  def makeDeckSelectable(selectable)
    @deck.makeSelectable(selectable)
  end

  def createDiscard(cards = Hand.new)
    cards.setHandLocation(@discardLocation)
    @discard = cards
  end

  def addToDiscard(card)
    @discard.add(cards)
  end

  def makeDiscardSelectable(selectable)
    @discard.makeSelectable(selectable)
  end

  def createPlayerHand(hashDir, hand = Hand.new)
    if(playerAvailable?(hashDir))
      @playerHands[hashDir] = hand
      repositionHands()
      return true
    end
    return false
  end

  def addToHand(hashDir, card)
    if(playerAvailable?(hashDir))
      @playerHands[hashDir].add(card)
      return true
    end
    return false
  end

  def removeFromHand(hashDir, index)
    if(playerAvailable?(hashDir))
      @playerHands[hashDir].add(card)
      return true
    end
    return false
  end

  def setFrontPlayer(hashDir)
    if(playerAvailable?(hashDir))
      difference = (LOCATION[hashDir] - LOCATION[@frontPlayer])
      newPlayerHandLocations = {}
      @playerHandLocations.each do |key, location|
        newPlayerHandLocations[numToDirectionHash(LOCATION[key] + difference)] = location
      end
      @playerHandLocations = newPlayerHandLocations
      repositionHands()
      @frontPlayer = hashDir
      return true
    end
    return false
  end

  def repositionHands
    @playerHands.each do |handKey, hand|
      location = @playerHandLocations[handKey]
      hand.setHandLocation(location)
    end
  end
  private :repositionHands

  def playerAvailable?(hashDir)
    return @playerHandLocations.has_key?(hashDir)
  end
  private :playerAvailable?

  def drawGame
    @playerHands.each do |handKey, hand|
      hand.draw
    end
    if(@deck != nil)
      @deck.draw
    end
    if(@discard != nil)
      @discard.draw
    end
  end

  def clicked(mouseX, mouseY)
    @playerHands.values.each do |hand|
      hand.clicked(mouseX, mouseY)
    end
  end

end

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