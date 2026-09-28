# frozen_string_literal: true

Haystack.register_patch(:graphql) do |config|
  if defined?(::GraphQL::Schema) && defined?(::GraphQL::Tracing::HaystackTrace) && ::GraphQL::Schema.respond_to?(:trace_with)
    ::GraphQL::Schema.trace_with(::GraphQL::Tracing::HaystackTrace, set_transaction_name: true)
  else
    # A gem graphql só oferece GraphQL::Tracing::SentryTrace (que chama Sentry.*),
    # então no Haystack a integração fica desligada
    config.logger.warn(Haystack::LOGGER_PROGNAME) { "A integração com GraphQL não é suportada no Haystack (a gem graphql não tem GraphQL::Tracing::HaystackTrace)." }
  end
end
