if defined?(::Delayed::Plugin)
  Haystack.logger.info('Loading Delayed Job integration')

  module Haystack
    module Integrations
      class DelayedPlugin < ::Delayed::Plugin
        callbacks do |lifecycle|
          lifecycle.around(:invoke_job) do |job, &block|
            invoke_with_instrumentation(job, block)
          end
        end

        def self.invoke_with_instrumentation(job, block)
          class_and_method_name = if job.payload_object.respond_to?(:haystack_name)
            job.payload_object.haystack_name
          else
            job.name
          end
          class_name, method_name = class_and_method_name.split('#')

          Haystack.monitor_transaction(
            'perform_job.delayed_job',
            :class    => class_name,
            :method   => method_name,
            :metadata => {
              :id       => job.id,
              :queue    => job.queue,
              :priority => job.priority || 0,
              :attempts => job.attempts || 0
            },
            :queue_start => job.created_at
          ) do
            block.call(job)
          end
        end
      end
    end
  end
  ::Delayed::Worker.plugins << Haystack::Integrations::DelayedPlugin
end
