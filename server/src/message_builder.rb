require 'json' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment

# Helper for building websocket messages to clients
class MessageBuilder
  # Builds messages that indicate to the client that something has changed (a player played/drew/discarded a card, etc.)
  # These should generally go to all players, since they'll affect visual game state
  def self.build_action_message(action)
    msg_hash = { "type": 'action' }
    msg_hash['msg'] = action
    JSON.generate(msg_hash)
  end

  # Builds an action message for adding a card to one of the hands.
  # If adding to a player's hand, requires subject_specifier to indicate which via the direction
  def self.build_add_card_message(card_suit, card_value, subject, subject_specifier = nil)
    msg = { "type": 'add_card', "subject": subject, "subject_specifier": subject_specifier,
            "card": { "suit": card_suit, "value": card_value } }
    build_action_message(msg)
  end

  # Builds an action message for adding a card to one of the hands.
  # If adding to a player's hand, requires subject_specifier to indicate which via the direction
  def self.build_remove_card_message(index, subject, subject_specifier = nil)
    msg = { "type": 'remove_card', "subject": subject, "subject_specifier": subject_specifier, "index": index }
    build_action_message(msg)
  end

  # Builds messages that indicate to the client that there is something they need to do (play and/or draw and/or discard a card)
  # These should only go to the relevant player
  def self.build_actionable_message(actionable)
    msg_hash = { "type": 'actionable' }
    msg_hash['msg'] = actionable
    JSON.generate(msg_hash)
  end

  # Builds a message that indicates to the client relevant information that does not change the game state
  #   nor is actionable (like the game having ended, or needing to wait on other players if playing simultaneously)
  def self.build_info_message(info)
    msg_hash = { "type": 'info' }
    msg_hash['msg'] = info
    JSON.generate(msg_hash)
  end
end
