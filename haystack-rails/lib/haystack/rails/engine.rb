# frozen_string_literal: true

require "haystack/rails/middleware/injector"

module Haystack
  # Sem isolate_namespace: o app hospedeiro (new-farmer) tem controllers no
  # namespace Haystack::, que passariam a usar as rotas (vazias) do engine.
  class Engine < ::Rails::Engine

    initializer 'haystack.add_middleware', before: 'ActionDispatch::ShowExceptions' do |app|
      app.middleware.insert_before ActionDispatch::ShowExceptions, Haystack::Rails::Middleware::Injector
    end

    # Apps sem asset pipeline (sem Sprockets) não têm config.assets: sem essa
    # checagem o boot quebrava; nesses apps o SDK do navegador fica desligado
    initializer 'haystack.assets.precompile' do |app|
      app.config.assets.precompile += %w[haystack/bundle.tracing.replay.min.js] if app.config.respond_to?(:assets)
    end
  end
end
