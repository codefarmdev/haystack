# frozen_string_literal: true

module Haystack
  module Rails
    module ControllerTransaction
      SPAN_ORIGIN = "auto.view.rails"

      def self.included(base)
        base.prepend_around_action(:haystack_around_action)
      end

      private

      def haystack_around_action
        if Haystack.initialized?
          haystack_set_request_context
          transaction_name = "#{self.class}##{action_name}"
          Haystack.get_current_scope.set_transaction_name(transaction_name, source: :view)
          Haystack.with_child_span(op: "view.process_action.action_controller", description: transaction_name, origin: SPAN_ORIGIN) do |child_span|
            if child_span
              begin
                result = yield
              ensure
                child_span.set_http_status(response.status)
                child_span.set_data(:format, request.format)
                child_span.set_data(:method, request.method)

                pii = Haystack.configuration.send_default_pii
                child_span.set_data(:path, pii ? request.fullpath : request.filtered_path)
                child_span.set_data(:params, pii ? request.params : request.filtered_parameters)
                child_span.set_data(:view_runtime, view_runtime) if respond_to?(:view_runtime, true) && view_runtime
              end

              result
            else
              yield
            end
          end
        else
          yield
        end
      ensure
        haystack_set_memory_usage if Haystack.initialized?
      end

      # Parâmetros e sessão (filtrados pelo filter_parameters do Rails) e o IP
      # do cliente vão para os erros e transações desta requisição, como o
      # Haystack antigo guardava
      def haystack_set_request_context
        Haystack.get_current_scope.set_extras(
          params: request.filtered_parameters.except("controller", "action"),
          session_data: haystack_filtered_session,
          client_ip: request.remote_ip
        )
      rescue StandardError => e
        Haystack.logger.debug("[Haystack] contexto da requisição indisponível: #{e.message}")
      end

      def haystack_filtered_session
        data = session.respond_to?(:to_hash) ? session.to_hash.except("_csrf_token") : {}
        Haystack::Rails.parameter_filter.filter(data)
      end

      # RSS do processo em MB (Linux); o Haystack antigo mandava o mesmo dado
      STATM_PATH = "/proc/self/statm"

      def haystack_set_memory_usage
        return unless File.readable?(STATM_PATH)

        rss_pages = File.read(STATM_PATH).split[1].to_i
        Haystack.get_current_scope.set_extras(memory_usage: (rss_pages * 4096 / 1024.0 / 1024.0).round(1))
      rescue StandardError
        nil
      end
    end
  end
end
