require 'haystack'
require 'capistrano/version'

if defined?(Capistrano::VERSION) && Gem::Version.new(Capistrano::VERSION) >= Gem::Version.new(3)
  # Capistrano 3+
  load File.expand_path('../integrations/capistrano/haystack.cap', __FILE__)
else
  # Capistrano 2
  require 'haystack/integrations/capistrano/capistrano_2_tasks'
end
