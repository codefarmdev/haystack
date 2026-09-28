# Configuração equivalente à dos projetos que usam o Haystack 1.0
Haystack.init do |config|
  config.dsn = ENV['HAYSTACK_DSN']
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  config.traces_sample_rate = 1.0
  # O health check não gera transação (é chamado a cada poucos segundos)
  config.traces_sampler = lambda do |contexto|
    env = contexto[:env]
    next 0.0 if env && env['PATH_INFO'] == '/saude'

    1.0
  end

  config.excluded_exceptions += ['ErroIgnorado']

  # Nos testes o replay de erro para poucos segundos depois do erro
  config.js.replay_after_error_seconds = Integer(ENV.fetch('HAYSTACK_REPLAY_AFTER_ERROR_SECONDS', '30'))
end
