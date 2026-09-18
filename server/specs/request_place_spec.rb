# frozen_string_literal: true

require 'rspec'
require 'rspec/mocks'
require 'json'
require_relative '../src/game'
require_relative '../src/tcp_client_handler'

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

RSpec.describe Game, '#handle_request_place_message' do
  let(:instructions_json) { JSON.generate(MINIMAL_INSTRUCTIONS) }

  subject(:game) do
    allow(IO).to receive(:read).and_return(instructions_json)
    Game.new('fake.json')
  end

  # Helpers to parse messages sent to a client after a tick
  def sent_action_messages(client)
    client.sent_messages.map { |raw| JSON.parse(raw) }
  end

  def sent_msg_types(client)
    sent_action_messages(client).map { |m| m.dig('msg', 'type') }
  end

  def add_and_connect(game, dir = nil)
    client = MockTcpClient.new
    game.add_player(client, dir)
    client
  end

  def request_place(client, place: nil)
    msg = { 'action' => 'request_place' }
    msg['place'] = place unless place.nil?
    client.receive(JSON.generate(msg))
  end

  # ---- tests ----

  describe 'when a player sends request_place with no place argument' do
    it 'marks that player as ready' do
      client = add_and_connect(game)
      request_place(client)
      # players_ready is private; drive its effect: run_game won't start without all ready
      # so we confirm via outgoing message instead
      game.tick
      expect(sent_msg_types(client)).to include('set_player_location')
    end

    it 'sends a set_player_location message back to the requesting player with their assigned direction' do
      client = add_and_connect(game)
      request_place(client)
      game.tick
      location_msg = sent_action_messages(client).find { |m| m.dig('msg', 'type') == 'set_player_location' }
      expect(location_msg).not_to be_nil
      expect(location_msg.dig('msg', 'location')).to eq('N')
    end

    it 'sends a player_connected message to the requesting player' do
      client = add_and_connect(game)
      request_place(client)
      game.tick
      expect(sent_msg_types(client)).to include('player_connected')
    end

    it 'includes the player direction in the player_connected message' do
      client = add_and_connect(game)
      request_place(client)
      game.tick
      connected_msg = sent_action_messages(client).find { |m| m.dig('msg', 'type') == 'player_connected' }
      expect(connected_msg.dig('msg', 'location')).to eq('N')
    end
  end

  describe 'when two players both send request_place' do
    it 'sends set_player_location to each player with their own direction' do
      north = add_and_connect(game)
      south = add_and_connect(game)
      request_place(north)
      request_place(south)
      game.tick

      north_loc_msg = sent_action_messages(north).find { |m| m.dig('msg', 'type') == 'set_player_location' }
      south_loc_msg = sent_action_messages(south).find { |m| m.dig('msg', 'type') == 'set_player_location' }

      expect(north_loc_msg.dig('msg', 'location')).to eq('N')
      expect(south_loc_msg.dig('msg', 'location')).to eq('S')
    end

    it 'notifies each player that the other is connected via player_connected' do
      north = add_and_connect(game)
      south = add_and_connect(game)
      request_place(north)
      request_place(south)
      game.tick

      # After south connects, north should receive a player_connected for south via inform_state
      north_connected_msgs = sent_action_messages(north).select { |m| m.dig('msg', 'type') == 'player_connected' }
      south_locations_seen = north_connected_msgs.map { |m| m.dig('msg', 'location') }
      expect(south_locations_seen).to include('S')
    end

    it 'does not send set_player_location to the other player' do
      north = add_and_connect(game)
      south = add_and_connect(game)
      request_place(north)
      game.tick

      # Only north sent request_place — south should not receive set_player_location
      expect(sent_msg_types(south)).not_to include('set_player_location')
    end
  end

  describe 'when a player disconnects after placing' do
    it 'sends player_disconnected to remaining connected players' do
      north = add_and_connect(game)
      south = add_and_connect(game)
      request_place(north)
      request_place(south)
      game.tick

      north.sent_messages.clear
      south.disconnect
      game.tick

      disconnected_msgs = sent_action_messages(north).select { |m| m.dig('msg', 'type') == 'player_disconnected' }
      expect(disconnected_msgs).not_to be_empty
      expect(disconnected_msgs.first.dig('msg', 'location')).to eq('S')
    end

    it 'does not send player_disconnected to the disconnected player themselves' do
      north = add_and_connect(game)
      south = add_and_connect(game)
      request_place(north)
      request_place(south)
      game.tick

      south.sent_messages.clear
      south.disconnect
      game.tick

      expect(sent_msg_types(south)).not_to include('player_disconnected')
    end
  end

  describe 'when a message has no action field' do
    it 'does not enqueue any outgoing messages' do
      client = add_and_connect(game)
      client.receive(JSON.generate({ 'not_action' => 'something' }))
      game.tick
      expect(client.sent_messages).to be_empty
    end
  end

  describe 'when a message has an unknown action' do
    it 'does not enqueue any outgoing messages' do
      client = add_and_connect(game)
      client.receive(JSON.generate({ 'action' => 'explode' }))
      game.tick
      expect(client.sent_messages).to be_empty
    end
  end
end
