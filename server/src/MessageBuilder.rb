require "json"

class MessageBuilder

  # Builds messages that indicate to the client that something has changed (a player played a card, a player drew a card, ect.)
  # These should generally go to all players, since they'll affect visual game state
  def self.buildActionMessage(action)
    msgHash = {"type": "action"}
    msgHash["msg"] = action
    return JSON.generate(msgHash)
  end

  # Builds an action message for adding a card to one of the hands. If adding to a player's hand, requires subjectSpecifier to indicate which via the direction
  def self.buildAddCardMessage(cardSuit, cardValue, subject, subjectSpecifier = nil)
    msg = { "type": "add_card", "subject": subject, "subjectSpecifier": subjectSpecifier, "card": { "suit": cardSuit, "value": cardValue }}
    return buildActionMessage(msg)
  end

  # Builds an action message for adding a card to one of the hands. If adding to a player's hand, requires subjectSpecifier to indicate which via the direction
  def self.buildRemoveCardMessage(index, subject, subjectSpecifier = nil)
    msg = { "type": "remove_card", "subject": subject, "subjectSpecifier": subjectSpecifier, "index": index }
    return buildActionMessage(msg)
  end

  # Builds messages that indicate to the client that there is something they need to do (play a card and/or draw a card and/or discard a card etc.)
  # These should only go to the relevant player
  def self.buildActionableMessage(actionable)
    msgHash = {"type": "actionable"}
    msgHash["msg"] = actionable
    return JSON.generate(msgHash)
  end

  # Builds a message that indicates to the client relevant information that does not change the game state nor is actionable (like the game having ended, or needing to wait on other players if playing simultaneously)
  def self.buildInfoMessage(info)
    msgHash = {"type": "info"}
    msgHash["msg"] = info
    return JSON.generate(msgHash)
  end

end