require "gosu"
require_relative "../cards/Hand"
require_relative "../Window.rb"

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

  def initialize
    # Assumes a 1920,1080 screen, can adjust from there by ratio of new screen sizes
    # TODO: Allow different screen sizes
    @playerHandLocations = {
      numToDirectionHash(0) => [750,                    1020-@@PlayerHandHeight, 750+@@PlayerHandWidth, 1020],
      numToDirectionHash(1) => [50,                     450,                     50+@@PlayerHandWidth,  450+@@PlayerHandHeight],
      numToDirectionHash(2) => [750,                    50,                      750+@@PlayerHandWidth, 50+@@PlayerHandHeight],
      numToDirectionHash(3) => [1800-@@PlayerHandWidth, 450,                     1800,                  450+@@PlayerHandHeight]
    }
    @frontPlayer = numToDirectionHash(0)
    @playerHands = {}
  end

  def createPlayerHand(hashDir, hand = Hand.new)
    if(playerAvailable?(hashDir))
      @playerHands[hashDir] = hand
      repositionHands()
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
      puts("front player set to #{@frontPlayer}")
      return true
    end
    return false
  end

  def repositionHands
    @playerHands.each do |handKey, hand|
      location = @playerHandLocations[handKey]
      hand.setHandLocation(location[0], location[1], location[2], location[3])
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
  end

  def clicked(mouseX, mouseY)
    @playerHands.values.each do |hand|
      hand.clicked(mouseX, mouseY)
    end
  end

end

gm = GameMaster.new()
sampleHands = {S: nil}
sampleCardDrawer = CardDrawer.new("../../resources/cards")
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

window = GameWindow.new(gm).show()