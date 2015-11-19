if defined?(::Sequel)
  Haystack.logger.info("Loading Sequel (#{ Sequel::VERSION }) integration")

  module Haystack
    module Integrations
      module Sequel
        # Add query instrumentation
        def log_yield(sql, args = nil)
          name    = 'sql.sequel'
          payload = {:sql => sql, :args => args}

          ActiveSupport::Notifications.instrument(name, payload) { yield }
        end
      end # Sequel
    end # Integrations
  end # Haystack

  # Register the extension...
  Sequel::Database.register_extension(
    :haystack_integration,
    Haystack::Integrations::Sequel
  )

  # ... and automatically add it to future instances.
  Sequel::Database.extension(:haystack_integration)
end
