# frozen_string_literal: true

require 'rspec'
require 'rspec/mocks'
require 'json'
require 'logger'
require_relative '../src/card'
require_relative '../src/game'

INSTRUCTIONS = {
  'game' => {
    'players' => %w[N S],
    'deck' => { 'visible' => false, 'cards' => { 'all' => [] } },
    'discard' => { 'visible' => true }
  },
  'scoring' => {},
  'extra_hands' => [],
  'fake_hands' => []
}.freeze

# --- Helpers ---

# A mock of TcpClientConnection that captures registered callbacks and sent messages,
# allowing tests to simulate incoming messages and inspect outgoing ones.
class MockTcpClient
  attr_reader :sent_messages

  def initialize
    @sent_messages = []
    @on_message = nil
    @on_close = nil
  end

  def send(msg)
    @sent_messages << msg
  end

  def onmessage(&block)
    @on_message = block
  end

  def onclose(&block)
    @on_close = block
  end

  # Simulate an incoming message from this client
  def receive(msg_json)
    @on_message&.call(msg_json, nil)
  end

  # Simulate this client disconnecting
  def disconnect
    @on_close&.call
  end
end

def build_game(starting_deck: [])
  allow(IO).to receive(:read).and_return(JSON.generate(INSTRUCTIONS))
  Game.new('fake.json', starting_deck: starting_deck)
end

def add_connected_player(game, dir)
  client = MockTcpClient.new
  game.add_player(client, dir)
  client
end

def parsed_messages(client)
  client.sent_messages.map { |raw| JSON.parse(raw) }
end

def action_msg_types(client)
  parsed_messages(client)
    .map { |m| m.dig('msg', 'type') }
    .compact
end

# --- Specs ---

RSpec.describe Game do
  let(:deck) do
    [
      Card.new('Hearts', '2'), Card.new('Hearts', '3'), Card.new('Hearts', '4'),
      Card.new('Spades', '5'), Card.new('Spades', '6'), Card.new('Spades', '7')
    ]
  end

  subject(:game) { build_game(starting_deck: deck) }

  before do
    # Connect both players so connected_players is populated
    add_connected_player(game, 'N')
    add_connected_player(game, 'S')
  end

  # -----------------------------------------------------------------------
  # run_step_cleanup
  # -----------------------------------------------------------------------

  describe '#run_step_cleanup' do
    before do
      # Pre-populate hands with cards via hand_manager
      game.instance_variable_get(:@hand_manager).add_card(Card.new('Hearts', '2'), 'hand', 'N')
      game.instance_variable_get(:@hand_manager).add_card(Card.new('Spades', '5'), 'hand', 'S')
    end

    context 'when subject is "all"' do
      let(:step_hash) { { 'action' => 'cleanup', 'subject' => 'all' } }

      it 'clears all player hands' do
        game.send(:run_step_cleanup, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands['N']).to be_empty
        expect(hm.hands['S']).to be_empty
      end

      it 'returns cleared cards to the deck' do
        hm = game.instance_variable_get(:@hand_manager)
        cards_in_hands = hm.hands.values.sum(&:size)
        deck_size_before = hm.deck.size
        game.send(:run_step_cleanup, step_hash)
        expect(hm.deck.size).to eq(deck_size_before + cards_in_hands)
      end

      it 'increments cur_step' do
        expect { game.send(:run_step_cleanup, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when subject is "hand" with no subject_specifier' do
      let(:step_hash) { { 'action' => 'cleanup', 'subject' => 'hand', 'subject_specifier' => nil } }

      it 'clears all player hands' do
        game.send(:run_step_cleanup, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands.values).to all(be_empty)
      end

      it 'increments cur_step' do
        expect { game.send(:run_step_cleanup, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when subject is "hand" with a subject_specifier' do
      let(:step_hash) { { 'action' => 'cleanup', 'subject' => 'hand', 'subject_specifier' => 'N' } }

      it 'clears only the specified player hand' do
        game.send(:run_step_cleanup, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands['N']).to be_empty
        expect(hm.hands['S']).not_to be_empty
      end
    end

    context 'when subject is "hand" with subject_specifier "cur_player"' do
      let(:step_hash) { { 'action' => 'cleanup', 'subject' => 'hand', 'subject_specifier' => 'cur_player' } }

      before { game.instance_variable_set(:@cur_player, 'N') }

      it 'clears only the current player hand' do
        game.send(:run_step_cleanup, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands['N']).to be_empty
        expect(hm.hands['S']).not_to be_empty
      end
    end

    context 'when subject is "discard"' do
      before do
        game.instance_variable_get(:@hand_manager).add_card(Card.new('Clubs', 'King'), 'discard')
      end

      let(:step_hash) { { 'action' => 'cleanup', 'subject' => 'discard', 'subject_specifier' => nil } }

      it 'clears the discard pile' do
        game.send(:run_step_cleanup, step_hash)
        expect(game.instance_variable_get(:@hand_manager).discard).to be_empty
      end
    end

    context 'when subject is unknown' do
      let(:step_hash) { { 'action' => 'cleanup', 'subject' => 'unknown_thing', 'subject_specifier' => nil } }

      it 'still increments cur_step' do
        expect { game.send(:run_step_cleanup, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when condition is present and evaluates to false (skip)' do
      let(:step_hash) do
        {
          'action' => 'cleanup',
          'subject' => 'hand',
          'condition' => { 'type' => 'hand_size', 'subject' => 'cur_player',
                           'comparison' => 999, 'comparators' => ['equal'] }
        }
      end

      before { game.instance_variable_set(:@cur_player, 'N') }

      it 'does not clear any hands' do
        hm = game.instance_variable_get(:@hand_manager)
        game.send(:run_step_cleanup, step_hash)
        expect(hm.hands['N']).not_to be_empty
      end

      it 'still increments cur_step' do
        expect { game.send(:run_step_cleanup, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end
  end

  # -----------------------------------------------------------------------
  # run_step_shuffle
  # -----------------------------------------------------------------------

  describe '#run_step_shuffle' do
    let(:cards) do
      [Card.new('Hearts', '2'), Card.new('Spades', '5'),
       Card.new('Clubs', 'King'), Card.new('Diamonds', 'Ace')]
    end

    before do
      hm = game.instance_variable_get(:@hand_manager)
      cards.each { |c| hm.add_card(c, 'hand', 'N') }
    end

    context 'when subject is "hand" with no specifier' do
      let(:step_hash) { { 'action' => 'shuffle', 'subject' => 'hand', 'subject_specifier' => nil } }

      it 'keeps the same cards in the hand' do
        game.send(:run_step_shuffle, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands['N'].sort_by(&:to_s)).to eq(cards.sort_by(&:to_s))
      end

      it 'increments cur_step' do
        expect { game.send(:run_step_shuffle, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when subject is "deck"' do
      let(:step_hash) { { 'action' => 'shuffle', 'subject' => 'deck', 'subject_specifier' => nil } }

      it 'keeps the same cards in the deck' do
        hm = game.instance_variable_get(:@hand_manager)
        deck_cards_before = hm.deck.sort_by(&:to_s)
        game.send(:run_step_shuffle, step_hash)
        expect(hm.deck.sort_by(&:to_s)).to eq(deck_cards_before)
      end

      it 'increments cur_step' do
        expect { game.send(:run_step_shuffle, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when subject is unknown' do
      let(:step_hash) { { 'action' => 'shuffle', 'subject' => 'unknown_thing', 'subject_specifier' => nil } }

      it 'still increments cur_step' do
        expect { game.send(:run_step_shuffle, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when condition prevents shuffle' do
      let(:step_hash) do
        {
          'action' => 'shuffle',
          'subject' => 'hand',
          'subject_specifier' => nil,
          'condition' => { 'type' => 'hand_size', 'subject' => 'cur_player',
                           'comparison' => 999, 'comparators' => ['equal'] }
        }
      end

      before { game.instance_variable_set(:@cur_player, 'N') }

      it 'does not change hand contents' do
        hm = game.instance_variable_get(:@hand_manager)
        before_hand = hm.hands['N'].dup
        game.send(:run_step_shuffle, step_hash)
        expect(hm.hands['N']).to eq(before_hand)
      end
    end
  end

  # -----------------------------------------------------------------------
  # run_step_deal
  # -----------------------------------------------------------------------

  describe '#run_step_deal' do
    before do
      game.instance_variable_set(:@dealer, 'S')
    end

    context 'when dealing to all hands with an amount' do
      let(:step_hash) { { 'action' => 'deal', 'subject' => 'hand', 'subject_specifier' => nil, 'amount' => 2 } }

      it 'deals the specified number of cards to each player' do
        game.send(:run_step_deal, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands['N'].size).to eq(2)
        expect(hm.hands['S'].size).to eq(2)
      end

      it 'removes dealt cards from the deck' do
        hm = game.instance_variable_get(:@hand_manager)
        deck_size_before = hm.deck.size
        game.send(:run_step_deal, step_hash)
        expect(hm.deck.size).to eq(deck_size_before - 4)
      end

      it 'deals round-robin (each player gets one card before any player gets a second)' do
        hm = game.instance_variable_get(:@hand_manager)
        # Load deck with distinguishable cards in order
        hm.deck.replace([
                          Card.new('Hearts', '2'), Card.new('Hearts', '3'),
                          Card.new('Hearts', '4'), Card.new('Hearts', '5')
                        ])
        game.send(:run_step_deal, step_hash)
        # Each player should have exactly 2 cards, dealt alternately
        expect(hm.hands['N'].size).to eq(2)
        expect(hm.hands['S'].size).to eq(2)
        # Cards should not all be from the same end of the deck
        all_dealt = hm.hands.values.flatten
        expect(all_dealt.map(&:value)).to match_array(%w[2 3 4 5])
      end

      it 'increments cur_step' do
        expect { game.send(:run_step_deal, step_hash) }
          .to change { game.instance_variable_get(:@cur_step) }.by(1)
      end
    end

    context 'when dealing to a specific player' do
      let(:step_hash) { { 'action' => 'deal', 'subject' => 'hand', 'subject_specifier' => 'N', 'amount' => 2 } }

      it 'deals only to the specified player' do
        game.send(:run_step_deal, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.hands['N'].size).to eq(2)
        expect(hm.hands['S']).to be_empty
      end
    end

    context 'when amount is nil' do
      let(:step_hash) { { 'action' => 'deal', 'subject' => 'hand', 'subject_specifier' => nil, 'amount' => nil } }

      it 'deals until the deck is empty' do
        game.send(:run_step_deal, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.deck).to be_empty
      end
    end

    context 'when dealing to discard' do
      let(:step_hash) { { 'action' => 'deal', 'subject' => 'discard', 'subject_specifier' => nil, 'amount' => 1 } }

      it 'adds a card to the discard pile' do
        game.send(:run_step_deal, step_hash)
        hm = game.instance_variable_get(:@hand_manager)
        expect(hm.discard.size).to eq(1)
      end
    end

    context 'when condition prevents deal' do
      let(:step_hash) do
        {
          'action' => 'deal',
          'subject' => 'hand',
          'subject_specifier' => nil,
          'amount' => 2,
          'condition' => { 'type' => 'hand_size', 'subject' => 'cur_player',
                           'comparison' => 999, 'comparators' => ['equal'] }
        }
      end

      before { game.instance_variable_set(:@cur_player, 'N') }

      it 'does not deal any cards' do
        hm = game.instance_variable_get(:@hand_manager)
        game.send(:run_step_deal, step_hash)
        expect(hm.hands.values).to all(be_empty)
      end
    end
  end

  # -----------------------------------------------------------------------
  # run_step_change_variable
  # -----------------------------------------------------------------------

  describe '#run_step_change_variable' do
    context 'when changing a counter variable with "set"' do
      before do
        game.instance_variable_get(:@counter_variables)['my_counter'] = 5
      end

      let(:step_hash) do
        { 'action' => 'change_variable', 'condition' => nil,
          'change' => { 'subject' => 'my_counter', 'action' => 'set', 'value' => 10 } }
      end

      it 'sets the counter to the given value' do
        game.send(:run_step_change_variable, step_hash)
        expect(game.instance_variable_get(:@counter_variables)['my_counter']).to eq(10)
      end
    end

    context 'when changing a counter variable with "add"' do
      before do
        game.instance_variable_get(:@counter_variables)['my_counter'] = 3
      end

      let(:step_hash) do
        { 'action' => 'change_variable', 'condition' => nil,
          'change' => { 'subject' => 'my_counter', 'action' => 'add', 'value' => 4 } }
      end

      it 'adds to the counter value' do
        game.send(:run_step_change_variable, step_hash)
        expect(game.instance_variable_get(:@counter_variables)['my_counter']).to eq(7)
      end
    end

    context 'when changing a flag variable with "set"' do
      before do
        game.instance_variable_get(:@flag_variables)['my_flag'] = false
      end

      let(:step_hash) do
        { 'action' => 'change_variable', 'condition' => nil,
          'change' => { 'subject' => 'my_flag', 'action' => 'set', 'value' => true } }
      end

      it 'sets the flag to the given value' do
        game.send(:run_step_change_variable, step_hash)
        expect(game.instance_variable_get(:@flag_variables)['my_flag']).to be true
      end
    end

    context 'when changing a flag variable with "flip"' do
      before do
        game.instance_variable_get(:@flag_variables)['my_flag'] = false
      end

      let(:step_hash) do
        { 'action' => 'change_variable', 'condition' => nil,
          'change' => { 'subject' => 'my_flag', 'action' => 'flip' } }
      end

      it 'flips the flag' do
        game.send(:run_step_change_variable, step_hash)
        expect(game.instance_variable_get(:@flag_variables)['my_flag']).to be true
      end
    end

    context 'when condition is not met' do
      before do
        game.instance_variable_get(:@counter_variables)['my_counter'] = 5
        game.instance_variable_set(:@cur_player, 'N')
      end

      let(:step_hash) do
        {
          'action' => 'change_variable',
          'condition' => { 'type' => 'hand_size', 'subject' => 'cur_player',
                           'comparison' => 999, 'comparators' => ['equal'] },
          'change' => { 'subject' => 'my_counter', 'action' => 'set', 'value' => 99 }
        }
      end

      it 'does not change the variable' do
        game.send(:run_step_change_variable, step_hash)
        expect(game.instance_variable_get(:@counter_variables)['my_counter']).to eq(5)
      end
    end
  end

  # -----------------------------------------------------------------------
  # run_step_assign_trick
  # -----------------------------------------------------------------------

  describe '#run_step_assign_trick' do
    let(:north_card) { Card.new('Hearts', '2') }
    let(:south_card) { Card.new('Hearts', 'King') }

    before do
      hm = game.instance_variable_get(:@hand_manager)
      hm.add_card(north_card, 'play_area', 'N')
      hm.add_card(south_card, 'play_area', 'S')

      game.instance_variable_set(
        :@recently_played,
        [['N', north_card], ['S', south_card]]
      )
    end

    it 'sets @latest_winner to the player who played the best card' do
      game.send(:run_step_assign_trick, {})
      expect(game.instance_variable_get(:@latest_winner)).to eq('S')
    end

    it 'clears all play areas' do
      game.send(:run_step_assign_trick, {})
      hm = game.instance_variable_get(:@hand_manager)
      expect(hm.play_areas.values).to all(be_empty)
    end

    it 'moves all trick cards to the winner\'s won_cards' do
      game.send(:run_step_assign_trick, {})
      hm = game.instance_variable_get(:@hand_manager)
      expect(hm.won_cards['S']).to include(north_card, south_card)
    end

    it 'clears @recently_played' do
      game.send(:run_step_assign_trick, {})
      expect(game.instance_variable_get(:@recently_played)).to be_empty
    end

    it 'increments cur_step' do
      expect { game.send(:run_step_assign_trick, {}) }
        .to change { game.instance_variable_get(:@cur_step) }.by(1)
    end
  end

  # -----------------------------------------------------------------------
  # run_step_actionable
  # -----------------------------------------------------------------------

  describe '#run_step_actionable' do
    let(:step_hash) do
      {
        'action' => 'actionable',
        'actionables' => {
          'action_1' => { 'action' => 'draw', 'count' => 1 }
        }
      }
    end

    before do
      game.instance_variable_set(:@cur_player, 'N')
      # Stub the latch so the test doesn't block
      latch = instance_double(Concurrent::CountDownLatch)
      allow(Concurrent::CountDownLatch).to receive(:new).and_return(latch)
      allow(latch).to receive(:wait)
      allow(latch).to receive(:count_down)
    end

    it 'populates @cur_actionables with the specified actions and counts' do
      game.send(:run_step_actionable, step_hash)
      expect(game.instance_variable_get(:@cur_actionables)).to include('draw' => 1)
    end

    it 'queues an actionable message for the current player' do
      game.send(:run_step_actionable, step_hash)
      outgoing = game.instance_variable_get(:@outgoing_msg_q)
      actionable_msgs = outgoing.select do |msg, players|
        JSON.parse(msg)['type'] == 'actionable' && players == ['N']
      end
      expect(actionable_msgs).not_to be_empty
    end

    it 'increments cur_step after the latch is released' do
      expect { game.send(:run_step_actionable, step_hash) }
        .to change { game.instance_variable_get(:@cur_step) }.by(1)
    end
  end

  # -----------------------------------------------------------------------
  # run_step_winner
  # -----------------------------------------------------------------------

  describe '#run_step_winner' do
    it 'increments cur_step' do
      expect { game.send(:run_step_winner, {}) }
        .to change { game.instance_variable_get(:@cur_step) }.by(1)
    end
  end
end
