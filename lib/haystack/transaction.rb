module Haystack
  class Transaction
    # Based on what Rails uses + some variables we'd like to show
    ENV_METHODS = %w(CONTENT_LENGTH AUTH_TYPE GATEWAY_INTERFACE
    PATH_TRANSLATED REMOTE_HOST REMOTE_IDENT REMOTE_USER REMOTE_ADDR
    REQUEST_METHOD SERVER_NAME SERVER_PORT SERVER_PROTOCOL REQUEST_URI PATH_INFO

    HTTP_X_REQUEST_START HTTP_X_MIDDLEWARE_START HTTP_X_QUEUE_START
    HTTP_X_QUEUE_TIME HTTP_X_HEROKU_QUEUE_WAIT_TIME HTTP_X_APPLICATION_START
    HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING HTTP_ACCEPT_LANGUAGE
    HTTP_CACHE_CONTROL HTTP_CONNECTION HTTP_USER_AGENT HTTP_FROM HTTP_NEGOTIATE
    HTTP_PRAGMA HTTP_REFERER HTTP_X_FORWARDED_FOR HTTP_CLIENT_IP).freeze

    def self.create(request_id, env, defaults={})
      Haystack.logger.debug("Creating transaction: #{request_id}")
      Thread.current[:haystack_transaction_id] = request_id
      Haystack::Transaction.new(request_id, env, defaults)
    end

    def self.current
      Haystack.transactions[Thread.current[:haystack_transaction_id]]
    end

    def self.complete_current!
      if current
        current.complete!
        Thread.current[:haystack_transaction_id] = nil
      else
        Haystack.logger.error('Trying to complete current, but no transaction present')
      end
    end

    attr_reader :request_id, :events, :process_action_event, :action, :exception,
                :env, :fullpath, :time, :tags, :kind, :queue_start, :paused, :params

    def initialize(request_id, env, defaults={})
      Haystack.logger.debug "Transaction.init"
      Haystack.transactions[request_id] = self
      @request_id           =  request_id
      @events               = []
      @process_action_event = nil
      @exception            = {}
      @env                  = env
      @params               = defaults[:params] || {}
      @tags                 = defaults[:tags] || {}
      @kind                 = defaults[:kind] || 'http_request'
      @action               = defaults[:action]
      @paused               = false
    end

    def sanitized_environment
      @sanitized_environment ||= {}
    end

    def sanitized_session_data
      @sanitized_session_data ||= {}
    end

    def sanitized_params
      @sanitized_params ||= {}
    end

    def request
      ::Rack::Request.new(@env) if @env
    end

    def set_tags(given_tags={})
      @tags.merge!(given_tags)
    end

    def pause!
      @paused = true
    end

    def resume!
      @paused = false
    end

    def set_process_action_event(event)
      return unless event && event.payload
      @process_action_event = event.dup
      if @process_action_event.payload[:controller]
        @action = "#{@process_action_event.payload[:controller]}##{@process_action_event.payload[:action]}"
      else
        @action = @process_action_event.payload[:action]
      end
      @kind = 'http_request'
      set_http_queue_start
    end

    def set_perform_job_event(event)
      return unless event && event.payload
      @process_action_event = event.dup
      @action = "#{@process_action_event.payload[:class]}##{@process_action_event.payload[:method]}"
      @kind = 'background_job'
      set_background_queue_start
    end

    def add_event(event)
      @events << event unless @paused == true
    end

    def add_exception(ex=nil)
      return unless ex
      Haystack.logger.debug("Adding #{ex.class.name} to transaction: #{request_id}")
      @time      = Time.now.utc.to_f
      @exception = {
        :exception  => ex.class.name,
        :message    => ex.message,
        :backtrace  => clean_backtrace(ex)
      }
    end

    def exception?
      exception.any?
    end

    def clean_backtrace(exception)
      return [] unless exception.backtrace.is_a?(Array)
      if defined?(::Rails)
        ::Rails.backtrace_cleaner.clean(exception.backtrace, nil)
      else
        exception.backtrace
      end
    end

    def slow_request?
      return false unless process_action_event && process_action_event.payload
      Haystack.config[:slow_request_threshold] <= process_action_event.duration
    end

    def slower?(transaction)
      process_action_event.duration > transaction.process_action_event.duration
    end

    def clear_events!
      events.clear
    end

    def truncate!
      return if truncated?
      process_action_event.truncate!
      events.clear
      tags.clear
      sanitized_environment.clear
      sanitized_session_data.clear
      sanitized_params.clear
      @env = nil
      @truncated = true
    end

    def truncated?
      !! @truncated
    end

    def convert_values_to_primitives!
      return if have_values_been_converted_to_primitives?
      @process_action_event.sanitize! if @process_action_event
      @events.each { |event| event.sanitize! }
      add_sanitized_context!
      @have_values_been_converted_to_primitives = true
    end

    def have_values_been_converted_to_primitives?
      !! @have_values_been_converted_to_primitives
    end

    def type
      return :exception if exception?
      return :slow_request if slow_request?
      :regular_request
    end

    def to_hash
      Formatter.new(self).to_hash
    end

    def complete!
      Thread.current[:haystack_transaction_id] = nil
      Haystack.transactions.delete(@request_id)
      if process_action_event || exception?
        if Haystack::IPC::Client.active?
          convert_values_to_primitives!
          Haystack::IPC::Client.enqueue(self)
        else
          Haystack.logger.debug("Enqueueing transaction: #{@request_id}")
          Haystack.enqueue(self)
        end
      else
        Haystack.logger.debug("Not processing transaction: #{@request_id} (#{events.length} events recorded)")
      end
    ensure
      Haystack.transactions.delete(@request_id)
    end

    def set_background_queue_start
      queue_start = process_action_event.payload[:queue_start]
      return unless queue_start
      Haystack.logger.debug("Setting background queue start: #{queue_start}")
      @queue_start = queue_start.to_f
    end

    def set_http_queue_start
      return unless env
      env_var = env['HTTP_X_QUEUE_START'] || env['HTTP_X_REQUEST_START']
      if env_var
        Haystack.logger.debug("Setting http queue start: #{env_var}")
        cleaned_value = env_var.tr('^0-9', '')
        unless cleaned_value.empty?
          value = cleaned_value.to_i
          [1_000_000.0, 1_000.0].each do |factor|
            @queue_start = value / factor
            break if @queue_start > 946_681_200.0 # Ok if it's later than 2000
          end
        end
      end
    end

    protected

    def add_sanitized_context!
      sanitize_environment!
      sanitize_session_data! if kind == 'http_request'
      sanitize_tags!
      sanitize_params!
      @env = nil
    end

    # Only keep tags if they meet the following criteria:
    # * Key is a symbol or string with less then 100 chars
    # * Value is a symbol or string with less then 100 chars
    # * Value is an integer
    def sanitize_tags!
      @tags.keep_if do |k,v|
        (k.is_a?(Symbol) || k.is_a?(String) && k.length <= 100) &&
        (((v.is_a?(Symbol) || v.is_a?(String)) && v.length <= 100) || (v.is_a?(Integer)))
      end
    end

    def sanitize_environment!
      return unless env && env.keys.any?
      ENV_METHODS.each do |key|
        sanitized_environment[key] = env[key]
      end
    end

    def sanitize_session_data!
      return unless request
      @sanitized_session_data = Haystack::ParamsSanitizer.sanitize(
        request.session.to_hash
      ) if Haystack.config[:skip_session_data] == false
      @fullpath = request.fullpath
    end

    def sanitize_params!
      return unless Haystack.config[:send_params]
      @sanitized_params = Haystack::ParamsSanitizer.sanitize(@params)
    end
  end
end
