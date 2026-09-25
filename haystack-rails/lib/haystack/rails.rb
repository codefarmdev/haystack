# frozen_string_literal: true

require "rails"
require "haystack"
require "haystack/integrable"
require "haystack/rails/tracing"
require "haystack/rails/configuration"
require "haystack/rails/engine"
require "haystack/rails/railtie"

module Haystack
  module Rails
    extend Integrable
    register_integration name: "rails", version: Haystack::Rails::VERSION

    # Filtro do filter_parameters do app (ActiveSupport::ParameterFilter só
    # existe a partir do Rails 6.0; no 5.2 a classe é a do ActionDispatch)
    def self.parameter_filter
      klass = defined?(::ActiveSupport::ParameterFilter) ? ::ActiveSupport::ParameterFilter : ::ActionDispatch::Http::ParameterFilter
      klass.new(::Rails.application.config.filter_parameters)
    end
  end
end
