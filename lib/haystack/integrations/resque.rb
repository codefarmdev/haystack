if defined?(::Resque)
  Haystack.logger.info('Loading Resque integration')

  module Haystack
    module Integrations
      module ResquePlugin
        def around_perform_resque_plugin(*args)
          Haystack.monitor_transaction(
            'perform_job.resque',
            :class => self.to_s,
            :method => 'perform'
          ) do
            yield
          end
        end
      end
    end
  end

  # Set up IPC
  Resque.before_first_fork do
    Haystack::IPC::Server.start if Haystack.active?
  end

  # In the fork, stop the normal agent startup
  # and stop listening to the server
  Resque.after_fork do |job|
    Haystack::IPC.forked! if Haystack.active?
  end

  # Extend the default job class with Haystack instrumentation
  Resque::Job.send(:extend, Haystack::Integrations::ResquePlugin)
end
