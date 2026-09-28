# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Haystack
  # Registra um deploy no Farmer (marcador nos gráficos e revisão no ar). Usado
  # pela task `haystack:deploy` do Capistrano (haystack/capistrano), mas não
  # depende dele.
  #
  # O token do projeto é o último segmento do path da DSN, e o servidor recebe
  # os marcadores no mesmo endpoint do Haystack 0.x: /api/requisicoes/markers.
  class DeployMarker
    class Result
      attr_reader :message

      def initialize(ok:, message:)
        @ok = ok
        @message = message
      end

      def ok?
        @ok
      end
    end

    MARKERS_PATH = "/api/requisicoes/markers"

    def self.notify(**options)
      new(**options).notify
    end

    def initialize(dsn:, revision:, user:, markers_url: nil, open_timeout: 5, read_timeout: 10)
      @dsn = dsn.to_s
      @revision = revision
      @user = user
      @markers_url = markers_url
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    # Nunca levanta exceção: o deploy não deve falhar por causa do marcador
    #
    # @return [Result]
    def notify
      return Result.new(ok: false, message: "HAYSTACK_DSN não definido; deploy não registrado") if @dsn.empty?

      uri = markers_uri
      http = ::Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout

      request = ::Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = { revision: @revision, user: @user }.to_json
      response = http.request(request)

      if response.is_a?(::Net::HTTPSuccess)
        Result.new(ok: true, message: "deploy #{@revision} registrado (#{@user})")
      else
        Result.new(ok: false, message: "falha ao registrar o deploy: HTTP #{response.code}")
      end
    rescue StandardError => e
      Result.new(ok: false, message: "falha ao registrar o deploy: #{e.class}: #{e.message}")
    end

    def markers_uri
      dsn_uri = URI.parse(@dsn)
      token = dsn_uri.path.split("/").last
      default_url = URI::Generic.build(scheme: dsn_uri.scheme, host: dsn_uri.host, port: dsn_uri.port, path: MARKERS_PATH).to_s

      uri = URI.parse(@markers_url || default_url)
      uri.query = URI.encode_www_form(token: token)
      uri
    end
  end
end
