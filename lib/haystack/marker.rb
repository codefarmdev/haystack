require 'haystack/integrations/capistrano/careful_logger'

module Haystack
  class Marker
    include Haystack::CarefulLogger

    attr_reader :marker_data, :config, :logger
    ACTION = 'markers'

    def initialize(marker_data, config, logger)
      @marker_data = marker_data
      @config = config
      @logger = logger
    end

    def transmit
      begin
        transmitter = Transmitter.new(ACTION, config)
        logger.info("Notifying Haystack of deploy with: revision: #{marker_data[:revision]}, user: #{marker_data[:user]}")
        result = transmitter.transmit(marker_data)
        if result == '200'
          logger.info('Haystack has been notified of this deploy!')
        else
          raise "#{result} at #{transmitter.uri}"
        end
      rescue Exception => e
        carefully_log_error(
          "Something went wrong while trying to notify Haystack: #{e}"
        )
      end
    end
  end
end
