raise 'This appsignal gem only works with rails' unless defined?(Rails)

module Appsignal
  class << self

    attr_accessor :subscriber, :event_payload_sanitizer

    def transactions
      @transactions ||= {}
    end

    def agent
      @agent ||= Appsignal::Agent.new
    end

    def config
      @config ||= Appsignal::Config.new(Rails.env).load
    end

    def event_payload_sanitizer
      @event_payload_sanitizer ||= proc { |event| event.payload }
    end

  end
end

require 'appsignal/config'
require 'appsignal/transmitter'
require 'appsignal/agent'
require 'appsignal/capistrano'
require 'appsignal/marker'
require 'appsignal/middleware'
require 'appsignal/transaction'
require 'appsignal/exception_notification'
require 'appsignal/version'
