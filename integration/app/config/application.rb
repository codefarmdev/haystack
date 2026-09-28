require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'sprockets/railtie'

Bundler.require(*Rails.groups)

module HaystackIntegracao
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # Filtrados nos logs, nos eventos/transações do Haystack e no script injetado
    config.filter_parameters += [:password, :cartao]

    # Jobs rodam em threads do próprio processo (sem fila externa)
    config.active_job.queue_adapter = :async

    config.time_zone = 'Brasilia'

    # Sprockets 3 (Rails 5.2) não lê os links do manifest.js
    config.assets.precompile += %w[turbo.js classico.js]
  end
end
