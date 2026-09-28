Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Os assets são precompilados na subida do container e servidos pelo próprio
  # Rails (como nos projetos atrás do nginx, mas sem o nginx)
  config.public_file_server.enabled = true
  config.assets.compile = false
  config.assets.js_compressor = nil
  config.assets.css_compressor = nil

  config.log_level = :info
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
end
