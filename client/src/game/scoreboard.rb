require 'concurrent' # rubocop:disable Style/FrozenStringLiteralComment
require 'gosu'

class Scoreboard
  BASE_SCORE_TEXT_HEIGHT = 20

  def initialize(player_names)
    @top_y = 0
    @bottom_y = 0
    @board_height = 0
    @left_x = 0
    @right_x = 0
    @board_width = 0

    @max_score_width = 0
    @score_height_limit = 0
    @score_scale = 1

    @player_names = player_names
    @scores = {}
    @scores_images = {}
    @need_reimage_scores = true
    @rw_lock = Concurrent::ReadWriteLock.new
  end

  def draw
    @rw_lock.with_read_lock do
      return if @board_height.zero? || @board_width.zero?

      if @need_reimage_scores
        @max_score_width = 0
        @need_reimage_scores = false
        @scores.each_key do |name|
          @scores_images[name] = Gosu::Image.from_text("#{@player_names[name]}: #{@scores[name]}",
                                                       BASE_SCORE_TEXT_HEIGHT)
          @max_score_width = [@scores_images[name].width, @max_score_width].max
        end
        @score_height_limit = @board_height / @scores_images.size
        @score_scale = [@board_width / @max_score_width, @score_height_limit / BASE_SCORE_TEXT_HEIGHT].min
      end

      # TODO: Draw Scoreboard edges?
      Gosu.draw_rect(@left_x, @top_y, @board_width, @board_height, Gosu::Color::GRAY)

      # scale to keep both width and height within bounds based on whichever needs to be shrunk more
      score_number = 0 # incrementer for positioning scores
      @scores_images.each_value do |image|
        image.draw(@left_x, @top_y + (@score_height_limit * score_number), 1, @score_scale, @score_scale)

        score_number += 1
      end
    end
  end

  # hash with names associated with scores
  def update_scores(scores)
    @rw_lock.with_write_lock do
      @need_reimage_scores = true
      @scores = scores
    end
  end

  def update_location(location)
    @rw_lock.with_write_lock do
      @left_x = location[0]
      @top_y = location[1]
      @right_x = location[2]
      @bottom_y = location[3]

      @board_width = @right_x - @left_x
      @board_height = @bottom_y - @top_y
    end
  end
end
