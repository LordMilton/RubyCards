# frozen_string_literal: true

require 'rspec'
require 'json'
require_relative '../src/game'

# Minimal valid game instructions JSON — enough for Game#initialize to complete
# without needing a real file on disk or any network/websocket dependencies
MINIMAL_INSTRUCTIONS = {
  'game' => {
    'players' => %w[N S],
    'deck' => {
      'visible' => false,
      'cards' => {
        'all' => [
          %w[Hearts_2 Hearts_3 Hearts_4],
          %w[Spades_2 Spades_3 Spades_4]
        ]
      }
    },
    'discard' => { 'visible' => true }
  },
  'scoring' => {},
  'extra_hands' => [],
  'fake_hands' => []
}.freeze

# Build a Game without touching the filesystem
def build_game
  instructions_json = JSON.generate(MINIMAL_INSTRUCTIONS)
  allow(IO).to receive(:read).and_return(instructions_json)
  Game.new('fake.json')
end

RSpec.describe 'num_to_direction_hash' do
  it 'returns the direction for a given number within range' do
    expect(num_to_direction_hash(0)).to eq('S')
    expect(num_to_direction_hash(1)).to eq('W')
    expect(num_to_direction_hash(2)).to eq('N')
    expect(num_to_direction_hash(3)).to eq('E')
  end

  it 'wraps around when the number exceeds the number of directions' do
    expect(num_to_direction_hash(4)).to eq('S')
    expect(num_to_direction_hash(5)).to eq('W')
  end

  it 'wraps around for negative numbers' do
    expect(num_to_direction_hash(-1)).to eq('E')
    expect(num_to_direction_hash(-4)).to eq('S')
  end
end

RSpec.describe Game do
  subject(:game) { build_game }

  # --- parse_cards_flat ---

  describe '#parse_cards_flat' do
    it 'parses a flat list of card strings into Card objects' do
      result = game.send(:parse_cards_flat, %w[Hearts_2 Spades_King])
      expect(result).to eq([Card.new('Hearts', '2'), Card.new('Spades', 'King')])
    end

    it 'parses a nested list by flattening it first' do
      result = game.send(:parse_cards_flat, [%w[Hearts_2 Hearts_3], ['Spades_4']])
      expect(result).to eq([
                             Card.new('Hearts', '2'),
                             Card.new('Hearts', '3'),
                             Card.new('Spades', '4')
                           ])
    end

    it 'returns an empty array for an empty list' do
      expect(game.send(:parse_cards_flat, [])).to eq([])
    end
  end

  # --- parse_cards_hierarchical ---

  describe '#parse_cards_hierarchical' do
    it 'parses a flat list preserving structure' do
      result = game.send(:parse_cards_hierarchical, %w[Hearts_2 Spades_King])
      expect(result).to eq([Card.new('Hearts', '2'), Card.new('Spades', 'King')])
    end

    it 'parses a nested list preserving nesting' do
      result = game.send(:parse_cards_hierarchical, [%w[Hearts_2 Hearts_3], ['Spades_4']])
      expect(result).to eq([
                             [Card.new('Hearts', '2'), Card.new('Hearts', '3')],
                             [Card.new('Spades', '4')]
                           ])
    end

    it 'returns an empty array for an empty list' do
      expect(game.send(:parse_cards_hierarchical, [])).to eq([])
    end
  end

  # --- parse_card_list ---

  describe '#parse_card_list' do
    it 'returns both flat and hierarchical representations' do
      input = [%w[Hearts_2 Hearts_3], ['Spades_4']]
      result = game.send(:parse_card_list, input)

      expect(result['flat']).to eq([
                                     Card.new('Hearts', '2'),
                                     Card.new('Hearts', '3'),
                                     Card.new('Spades', '4')
                                   ])
      expect(result['hier']).to eq([
                                     [Card.new('Hearts', '2'), Card.new('Hearts', '3')],
                                     [Card.new('Spades', '4')]
                                   ])
    end
  end

  # --- compare_values ---

  describe '#compare_values' do
    it 'returns true when equal and comparator is "equal"' do
      expect(game.send(:compare_values, 5, 5, ['equal'])).to be true
    end

    it 'returns false when not equal and comparator is "equal"' do
      expect(game.send(:compare_values, 4, 5, ['equal'])).to be false
    end

    it 'returns true when current is less and comparator is "less"' do
      expect(game.send(:compare_values, 3, 5, ['less'])).to be true
    end

    it 'returns false when current is not less and comparator is "less"' do
      expect(game.send(:compare_values, 5, 5, ['less'])).to be false
    end

    it 'returns true when current is greater and comparator is "greater"' do
      expect(game.send(:compare_values, 6, 5, ['greater'])).to be true
    end

    it 'returns false when current is not greater and comparator is "greater"' do
      expect(game.send(:compare_values, 5, 5, ['greater'])).to be false
    end

    it 'returns true when any comparator in the list matches' do
      expect(game.send(:compare_values, 5, 5, %w[less equal])).to be true
      expect(game.send(:compare_values, 3, 5, %w[less equal])).to be true
    end

    it 'returns false when no comparator matches' do
      expect(game.send(:compare_values, 6, 5, %w[less equal])).to be false
    end

    it 'returns true for unknown comparators (fail-safe to avoid infinite loops)' do
      expect(game.send(:compare_values, 1, 2, ['unknown_comparator'])).to be true
    end
  end

  # --- score_cards ---

  describe '#score_cards' do
    let(:scoring_method) do
      {
        'Hearts_2' => 2,
        'Spades_King' => 10,
        'Clubs_Ace' => 15
      }
    end

    it 'sums the scores of all cards' do
      cards = [Card.new('Hearts', '2'), Card.new('Spades', 'King')]
      expect(game.send(:score_cards, cards, scoring_method)).to eq(12)
    end

    it 'scores unknown cards as 0' do
      cards = [Card.new('Diamonds', '7')]
      expect(game.send(:score_cards, cards, scoring_method)).to eq(0)
    end

    it 'returns 0 for an empty hand' do
      expect(game.send(:score_cards, [], scoring_method)).to eq(0)
    end

    it 'correctly scores a mix of known and unknown cards' do
      cards = [Card.new('Hearts', '2'), Card.new('Diamonds', '7'), Card.new('Clubs', 'Ace')]
      expect(game.send(:score_cards, cards, scoring_method)).to eq(17)
    end
  end

  # --- score_cards_x_of_a_kind ---

  describe '#score_cards_x_of_a_kind' do
    let(:scoring_method) { { '2' => 1, '3' => 6, '4' => 12 } }

    it 'scores a pair (2 of a kind)' do
      cards = [Card.new('Hearts', '2'), Card.new('Spades', '2')]
      expect(game.send(:score_cards_x_of_a_kind, cards, scoring_method)).to eq(1)
    end

    it 'scores three of a kind' do
      cards = [Card.new('Hearts', '2'), Card.new('Spades', '2'), Card.new('Clubs', '2')]
      expect(game.send(:score_cards_x_of_a_kind, cards, scoring_method)).to eq(6)
    end

    it 'scores four of a kind' do
      cards = [
        Card.new('Hearts', '2'), Card.new('Spades', '2'),
        Card.new('Clubs', '2'), Card.new('Diamonds', '2')
      ]
      expect(game.send(:score_cards_x_of_a_kind, cards, scoring_method)).to eq(12)
    end

    it 'scores multiple independent sets' do
      cards = [
        Card.new('Hearts', '2'), Card.new('Spades', '2'), # pair
        Card.new('Hearts', '5'), Card.new('Spades', '5'), Card.new('Clubs', '5') # three of a kind
      ]
      expect(game.send(:score_cards_x_of_a_kind, cards, scoring_method)).to eq(7)
    end

    # TODO: Implement handling of larger sets than defined
    "
    it 'scores based on the smallest defined set size when set size is larger than all defined sets' do
      cards = [
        Card.new('Hearts', '2'),
        Card.new('Spades', '2'),
        Card.new('Hearts', '2'),
        Card.new('Spades', '2'),
        Card.new('Hearts', '2')
      ]
      expect(game.send(:score_cards_x_of_a_kind, cards, scoring_method)).to eq(20)
    end
    "

    it 'returns 0 when no scoring rule matches the set size or smaller' do
      cards = [Card.new('Hearts', '2')] # single card, no rule for '1'
      expect(game.send(:score_cards_x_of_a_kind, cards, scoring_method)).to eq(0)
    end
  end

  # --- score_cards_straight ---

  describe '#score_cards_straight' do
    let(:scoring_method) { { 'min_size' => 3, 'score_per_card' => 1 } }

    it 'finds a simple straight' do
      cards = [Card.new('Hearts', '2'), Card.new('Hearts', '3'), Card.new('Hearts', '4')]
      score = game.send(:score_cards_straight, cards, scoring_method)
      expect(score).to eq(3)
    end

    it 'treats cards that cannot extend any straight as solo straights of length 1' do
      cards = [Card.new('Hearts', '2'), Card.new('Hearts', '5')]
      score = game.send(:score_cards_straight, cards, scoring_method)
      expect(score).to eq(0)
    end

    it 'finds a straight across face cards' do
      cards = [Card.new('Hearts', 'Jack'), Card.new('Hearts', 'Queen'), Card.new('Hearts', 'King')]
      score = game.send(:score_cards_straight, cards, scoring_method)
      expect(score).to eq(3)
    end

    it 'finds two separate straights in the same hand' do
      cards = [
        Card.new('Hearts', '2'), Card.new('Hearts', '3'), Card.new('Hearts', '4'),
        Card.new('Spades', '8'), Card.new('Spades', '9'), Card.new('Spades', '10')
      ]
      score = game.send(:score_cards_straight, cards, scoring_method)
      expect(score).to eq(6)
    end

    # TODO: Implement wrapping
    "
    it 'when wrapping is true, finds straights that wrap from high to low' do
      scoring_method_flush = scoring_method.merge('wrapping' => true)
      cards = [
        Card.new('Hearts', 'Ace'),
        Card.new('Spades', 'Queen'),
        Card.new('Hearts', 'King')
      ]
      score = game.send(:score_cards_straight, cards, scoring_method_flush)
      # No cross-suit straights, each card is isolated in its own suit group
      expect(score).to eq(3)
    end
    "

    it 'when same_suit is true, does not count a straight across different suits' do
      scoring_method_flush = scoring_method.merge('same_suit' => true)
      cards = [
        Card.new('Hearts', '2'),
        Card.new('Spades', '3'),
        Card.new('Hearts', '4')
      ]
      score = game.send(:score_cards_straight, cards, scoring_method_flush)
      # No cross-suit straights, each card is isolated in its own suit group
      expect(score).to eq(0)
    end

    it 'when same_suit is true, finds a flush straight' do
      scoring_method_flush = scoring_method.merge('same_suit' => true)
      cards = [
        Card.new('Hearts', '2'),
        Card.new('Hearts', '3'),
        Card.new('Hearts', '4')
      ]
      score = game.send(:score_cards_straight, cards, scoring_method_flush)
      expect(score).to eq(3)
    end

    it 'scores a larger straight as such and does not score it as multiple smaller straights' do
      cards = [
        Card.new('Hearts', '2'),
        Card.new('Hearts', '3'),
        Card.new('Hearts', '4'),
        Card.new('Spades', '5')
      ]
      score = game.send(:score_cards_straight, cards, scoring_method)
      expect(score).to eq(4)
    end
  end

  # --- score_cards_flush ---

  describe '#score_cards_flush' do
    let(:scoring_method) { { 'min_size' => 3, 'score_per_card' => 1 } }

    it 'finds a flush' do
      cards = [
        Card.new('Hearts', '2'),
        Card.new('Hearts', '5'),
        Card.new('Hearts', 'King')
      ]
      expect(game.send(:score_cards_flush, cards, scoring_method)).to be > 0
    end

    it 'returns 0 when no suit has enough cards to meet min_size' do
      cards = [Card.new('Hearts', '2'), Card.new('Spades', '3')]
      expect(game.send(:score_cards_flush, cards, scoring_method)).to eq(0)
    end

    it 'scores each suit group independently' do
      cards = [
        Card.new('Hearts', '2'), Card.new('Hearts', '3'), Card.new('Hearts', '4'),
        Card.new('Spades', '5'), Card.new('Spades', '6'), Card.new('Spades', '7')
      ]
      result = game.send(:score_cards_flush, cards, scoring_method)
      expect(result).to eq(6) # 3 hearts + 3 spades
    end
  end
end
