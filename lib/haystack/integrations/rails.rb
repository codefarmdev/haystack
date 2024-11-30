if defined?(::Rails)
  Haystack.logger.info("Loading Rails (#{Rails.version}) integration")

  module Haystack
    module Integrations
      class Railtie < ::Rails::Railtie
        initializer 'haystack.configure_rails_initialization' do |app|
          Haystack::Integrations::Railtie.initialize_haystack(app)
        end

        def self.initialize_haystack(app)
          # Start logger
          Haystack.start_logger(Rails.root.join('log'))

          # Load config
          Haystack.config = Haystack::Config.new(
            Rails.root,
            ENV.fetch('HAYSTACK_APP_ENV', Rails.env),
            :name => Rails.application.class.respond_to?(:parent_name) ? Rails.application.class.parent_name : Rails.application.class.module_parent_name
          )

          app.middleware.insert_before(
            ActionDispatch::RemoteIp,
            Haystack::Rack::Listener
          )

          if Haystack.config.active? &&
            Haystack.config[:enable_frontend_error_catching] == true
            app.middleware.insert_before(
              Haystack::Rack::Listener,
              Haystack::Rack::JSExceptionCatcher,
            )
          end

          Haystack.start
        end
      end
    end
  end
end
