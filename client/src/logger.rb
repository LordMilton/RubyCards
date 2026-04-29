require 'logger' # rubocop:disable Layout/EndOfLine,Style/FrozenStringLiteralComment

# Logging utility, use instead of base logger for formatting
module MyLogger
  def logger
    @logger ||= begin
      logger = Logger.new($stdout)
      logger.level = Logger::DEBUG
      formatter = Logger::Formatter.new
      formatter.datetime_format = '%H:%M:%S.%2N '
      logger.formatter = proc { |severity, datetime, progname, msg|
        formatter.call(severity, datetime, progname || self.class.name, msg.dump)
      }
      logger
    end
  end
end
