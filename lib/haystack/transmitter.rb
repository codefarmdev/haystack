require 'net/http'
require 'net/https'
require 'uri'
require 'rack/utils'
require 'json'

module Haystack
  class Transmitter
    CONTENT_TYPE = 'application/json; charset=UTF-8'.freeze
    CONTENT_ENCODING = 'gzip'.freeze
    CA_FILE_PATH = File.expand_path(File.join(__FILE__, '../../../resources/cacert.pem'))

    HTTP_ERRORS = [
      EOFError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EINVAL,
      Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError,
      Net::ProtocolError,
      Timeout::Error,
      OpenSSL::SSL::SSLError
    ]

    attr_reader :config, :action

    def initialize(action, config=Haystack.config)
      @action = action
      @config = config
    end

    def uri
      @uri ||= URI("#{config[:endpoint]}/#{action}").tap do |uri|
        uri.query = ::Rack::Utils.build_query({
          :token => config[:push_api_key],
          :name => config[:name],
          :environment => config.env,
          :hostname => Socket.gethostname,
          :gem_version => Haystack::VERSION
        })
      end
    end

    # Accepts a string or `Haystack::ZippedPayload`
    # If no `Haystack::ZippedPayload` is given, it will convert it to one.
    def transmit(payload)
      unless payload.is_a?(Haystack::ZippedPayload)
        payload = Haystack::ZippedPayload.new(payload)
      end
      Haystack.logger.info "Transmitting payload to #{uri}"
      http_client.request(http_post(payload)).code
    end

    protected

    def http_post(payload)
      Net::HTTP::Post.new(uri.request_uri).tap do |request|
        request['Content-Type'] = CONTENT_TYPE
        # request['Content-Encoding'] = CONTENT_ENCODING
        request.body = payload.body
      end
    end

    def http_client
      client = if config[:http_proxy]
        Net::HTTP.new(uri.host, uri.port, proxy_addr, proxy_port)
      else
        Net::HTTP.new(uri.host, uri.port)
      end

      client.tap do |http|
        if uri.scheme == 'https'
          http.use_ssl     = true
          http.ssl_version = :TLSv1_2
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.ca_file     = CA_FILE_PATH
        end
      end
    end

    def proxy_uri
      @proxy_uri ||= URI.parse(config[:http_proxy])
    end

    def proxy_addr
      if config[:http_proxy]
        proxy_uri.host
      else
        nil
      end
    end

    def proxy_port
      if config[:http_proxy]
        proxy_uri.port
      else
        nil
      end
    end
  end
end
