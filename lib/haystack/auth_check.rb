module Haystack
  class AuthCheck
    ACTION = 'auth'.freeze

    attr_reader :config, :logger

    def initialize(config, logger)
      @config = config
      @logger = logger
    end

    def perform
      Haystack::Transmitter.new(ACTION, config).transmit({})
    end

    def perform_with_result
      begin
        status = perform
        case status
        when '200'
          result = 'Haystack has confirmed authorization!'
        when '401'
          result = 'API key not valid with Haystack...'
        else
          result = 'Could not confirm authorization: '\
                   "#{status.nil? ? 'nil' : status}"
        end
        [status, result]
      rescue Exception => e
        result = 'Something went wrong while trying to '\
                 "authenticate with Haystack: #{e}"
        [nil, result]
      end
    end
  end
end
