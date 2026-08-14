# initial line for rubocop disables # rubocop:disable Style/FrozenStringLiteralComment
require_relative './logger'

# Helper class for handling relative seat placements
class SeatPlacements
  val SEAT_ORDER = -%w[N NE E SE S SW W NW]

  include MyLogger

  attr_reader :seats

  # @param seats:Array<String> All seats in the game as their shortened directions ('NE', 'S')
  def initialize(seats)
    @seats = seats.sort do |seat1, seat2|
      SEAT_ORDER.index(seat1) <=> SEAT_ORDER.index(seat2)
    end
  end

  def next(seat)
    get_nth_next(seat, 1)
  end

  def nth_next(seat, nth)
    logger.warn('Seeking further ahead than we have seats, kinda weird...') if nth >= @seats.size

    @seats[(@seats.index(seat) + nth) % @seats.size]
  end

  def last(seat)
    get_nth_last(seat, 1)
  end

  def nth_last(seat, nth)
    logger.warn('Seeking further behind than we have seats, kinda weird...') if nth >= @seats.size

    @seats[(@seats.index(seat) - nth) % @seats.size]
  end
end
