require 'haystack'

module Haystack::Integrations
  module PadrinoPlugin
    def self.init
      Haystack.logger.info("Loading Padrino (#{Padrino::VERSION}) integration")

      root             = Padrino.mounted_root
      Haystack.config = Haystack::Config.new(root, Padrino.env)

      Haystack.start_logger(File.join(root, 'log'))
      Haystack.start

      if Haystack.active?
        Padrino.use(Haystack::Rack::Listener)
      end
    end
  end
end

module Padrino::Routing::InstanceMethods
  alias route_without_haystack route!

  def route!(base = settings, pass_block = nil)
    if env['sinatra.static_file']
      route_without_haystack(base, pass_block)
    else
      request_payload = {
        :params  => request.params,
        :session => request.session,
        :method  => request.request_method,
        :path    => request.path
      }
      ActiveSupport::Notifications.instrument('process_action.padrino', request_payload) do |request_payload|
        begin
          route_without_haystack(base, pass_block)
        rescue => e
          Haystack.add_exception(e); raise e
        ensure
          request_payload[:action] = get_payload_action(request)
        end
      end
    end
  end

  def get_payload_action(request)
    # Short-circut is there's no request object to obtain information from
    return "#{settings.name}" if request.nil?

    # Older versions of Padrino work with a route object
    route_obj = defined?(request.route_obj) && request.route_obj
    if route_obj && route_obj.respond_to?(:original_path)
      return "#{settings.name}:#{request.route_obj.original_path}"
    end

    # Newer versions expose the action / controller on the request class
    request_data = request.respond_to?(:action) ? request.action : request.fullpath
    "#{settings.name}:#{request.controller}##{request_data}"
  end
end

Padrino.after_load do
  Haystack::Integrations::PadrinoPlugin.init
end
