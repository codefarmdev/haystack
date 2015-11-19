module Haystack
  module Rack
    class Listener
      def initialize(app, options = {})
        Haystack.logger.debug 'Initializing Haystack::Rack::Listener'
        @app, @options = app, options
      end

      def call(env)
        if Haystack.active?
          call_with_haystack_monitoring(env)
        else
          @app.call(env)
        end
      end

      def call_with_haystack_monitoring(env)
        Haystack::Transaction.create(request_id(env), env)
        @app.call(env)
      rescue Exception => exception
        Haystack.add_exception(exception)
        raise exception
      ensure
        Haystack::Transaction.complete_current!
      end

      def request_id(env)
        env['action_dispatch.request_id'] || SecureRandom.uuid
      end
    end
  end
end
