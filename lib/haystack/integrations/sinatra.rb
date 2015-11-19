require 'haystack'

Haystack.logger.info("Loading Sinatra (#{Sinatra::VERSION}) integration")

app_settings = ::Sinatra::Application.settings
Haystack.config = Haystack::Config.new(
  app_settings.root,
  app_settings.environment
)

Haystack.start_logger(app_settings.root)

Haystack.start

if Haystack.active?
  ::Sinatra::Application.use(Haystack::Rack::Listener)
  ::Sinatra::Application.use(Haystack::Rack::SinatraInstrumentation)
end
