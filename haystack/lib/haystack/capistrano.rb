# frozen_string_literal: true

# Marcador de deploy (Capistrano 3): no deploy.rb, `require 'haystack/capistrano'`
# e um hook como `before 'puma:restart', 'haystack:deploy'`.
load File.expand_path("integrations/capistrano/haystack.cap", __dir__)
