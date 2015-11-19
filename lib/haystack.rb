require 'logger'
require 'rack'
require 'thread_safe'
require 'securerandom'

begin
  require 'active_support/notifications'
rescue LoadError
  require 'vendor/active_support/notifications'
end

module Haystack
  class << self
    attr_accessor :config, :logger, :agent, :in_memory_log

    def load_integrations
      require 'haystack/integrations/delayed_job'
      require 'haystack/integrations/passenger'
      require 'haystack/integrations/unicorn'
      require 'haystack/integrations/sidekiq'
      require 'haystack/integrations/resque'
      require 'haystack/integrations/sequel'
    end

    def load_instrumentations
      require 'haystack/instrumentations/net_http' if config[:instrument_net_http]
    end

    def extensions
      @extensions ||= []
    end

    def initialize_extensions
      Haystack.logger.debug('Initializing extensions')
      extensions.each do |extension|
        Haystack.logger.debug("Initializing #{extension}")
        extension.initializer
      end
    end

    def start
      if config
        if config[:debug]
          logger.level = Logger::DEBUG
        else
          logger.level = Logger::INFO
        end
        if config.active?
          logger.info("Starting Haystack #{Haystack::VERSION} on #{RUBY_VERSION}/#{RUBY_PLATFORM}")
          load_integrations
          load_instrumentations
          initialize_extensions
          @agent = Haystack::Agent.new
          at_exit do
            logger.debug('Running at_exit block')
            @agent.send_queue
          end
        else
          logger.info("Not starting, not active for #{config.env}")
        end
      else
        logger.error('Can\'t start, no config loaded')
      end
    end

    # Convenience method for adding a transaction to the queue. This queue is
    # managed and is periodically pushed to Haystack.
    #
    # @return [ true ] True.
    #
    # @since 0.5.0
    def enqueue(transaction)
      return unless active?
      agent.enqueue(transaction)
    end

    def monitor_transaction(name, payload={})
      unless active?
        yield
        return
      end

      begin
        Haystack::Transaction.create(SecureRandom.uuid, ENV)
        ActiveSupport::Notifications.instrument(name, payload) do
          yield
        end
      rescue Exception => exception
        Haystack.add_exception(exception)
        raise exception
      ensure
        Haystack::Transaction.complete_current!
      end
    end

    def listen_for_exception(&block)
      yield
    rescue Exception => exception
      send_exception(exception)
      raise exception
    end

    def send_exception(exception, tags=nil)
      return if !active? || is_ignored_exception?(exception)
      unless exception.is_a?(Exception)
        logger.error('Can\'t send exception, given value is not an exception')
        return
      end
      transaction = Haystack::Transaction.create(SecureRandom.uuid, nil)
      transaction.add_exception(exception)
      transaction.set_tags(tags) if tags
      transaction.complete!
      Haystack.agent.send_queue
    end

    def add_exception(exception)
      return if !active? ||
                Haystack::Transaction.current.nil? ||
                exception.nil? ||
                is_ignored_exception?(exception)
      Haystack::Transaction.current.add_exception(exception)
    end

    def tag_request(params={})
      return unless active?
      transaction = Haystack::Transaction.current
      return false unless transaction
      transaction.set_tags(params)
    end
    alias :tag_job :tag_request

    def transactions
      @transactions ||= {}
    end

    def logger
      @in_memory_log = StringIO.new unless @in_memory_log
      @logger ||= Logger.new(@in_memory_log).tap do |l|
        l.level = Logger::INFO
        l.formatter = Logger::Formatter.new
      end
    end

    def start_logger(path)
      if path && File.writable?(path) &&
         !ENV['DYNO'] &&
         !ENV['SHELLYCLOUD_DEPLOYMENT']
        @logger = Logger.new(File.join(path, 'haystack.log'))
        @logger.formatter = Logger::Formatter.new
      else
        @logger = Logger.new($stdout)
        @logger.formatter = lambda do |severity, datetime, progname, msg|
          "haystack: #{msg}\n"
        end
      end
      @logger.level = Logger::INFO
      @logger << @in_memory_log.string if @in_memory_log
    end

    def post_processing_middleware
      @post_processing_chain ||= Haystack::Aggregator::PostProcessor.default_middleware
      yield @post_processing_chain if block_given?
      @post_processing_chain
    end

    def active?
      config && config.active? &&
        agent && agent.active?
    end

    def is_ignored_exception?(exception)
      Haystack.config[:ignore_exceptions].include?(exception.class.name)
    end

    def is_ignored_action?(action)
      Haystack.config[:ignore_actions].include?(action)
    end

    # Convenience method for skipping instrumentations around a block of code.
    #
    # @since 0.8.7
    def without_instrumentation
      Haystack::Transaction.current.pause! if Haystack::Transaction.current
      yield
    ensure
      Haystack::Transaction.current.resume! if Haystack::Transaction.current
    end
  end
end

require 'haystack/agent'
require 'haystack/event'
require 'haystack/aggregator'
require 'haystack/aggregator/post_processor'
require 'haystack/aggregator/middleware'
require 'haystack/auth_check'
require 'haystack/config'
require 'haystack/marker'
require 'haystack/rack/listener'
require 'haystack/rack/instrumentation'
require 'haystack/rack/sinatra_instrumentation'
require 'haystack/rack/js_exception_catcher'
require 'haystack/params_sanitizer'
require 'haystack/transaction'
require 'haystack/transaction/formatter'
require 'haystack/transaction/params_sanitizer'
require 'haystack/transmitter'
require 'haystack/zipped_payload'
require 'haystack/ipc'
require 'haystack/version'
require 'haystack/integrations/rails'
require 'haystack/js_exception_transaction'
