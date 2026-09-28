# frozen_string_literal: true

# Farmer falso para a suíte de integração: recebe o que o Haystack envia (gem
# Ruby e SDK do navegador), decodifica os envelopes e guarda tudo em memória
# para os testes consultarem.
#
#   POST /api/v2/requests/api/:token/envelope   envelope do SDK (igual ao Farmer)
#   POST /api/requisicoes/markers?token=...      marcador de deploy (haystack:deploy)
#   GET  /_recebidos                              tudo o que chegou (JSON)
#   DELETE /_recebidos                            limpa
#   GET  /_saude                                  200 quando está no ar
#
# Com DUMP_DIR definido, o corpo bruto de cada envelope também é gravado lá
# (é assim que as fixtures de contrato do Farmer são geradas).

require "json"
require "zlib"
require "stringio"
require "webrick"
require "fileutils"
require "time"

module HaystackReceiver
  class EnvelopeParser
    # Formato: https://develop.sentry.dev/sdk/envelopes/
    # linha 1: cabeçalho do envelope; depois pares cabeçalho do item + payload.
    # O payload tem `length` bytes quando o cabeçalho informa, senão vai até o \n.
    def self.parse(raw)
      io = StringIO.new(raw.b)
      header = JSON.parse(io.gets.to_s)
      items = []

      until io.eof?
        line = io.gets
        next if line.nil? || line.strip.empty?

        item_header = JSON.parse(line)
        payload = if item_header["length"]
          data = io.read(item_header["length"])
          io.gets # \n depois do payload
          data
        else
          io.gets.to_s.chomp
        end

        items << { "type" => item_header["type"], "header" => item_header, "payload" => decode_payload(item_header["type"], payload) }
      end

      { "header" => header, "items" => items }
    end

    def self.decode_payload(type, payload)
      return decode_replay_recording(payload) if type == "replay_recording"

      JSON.parse(payload.force_encoding("UTF-8"))
    rescue JSON::ParserError
      { "_raw" => payload.force_encoding("UTF-8").scrub }
    end

    # replay_recording: {"segment_id":N}\n + eventos rrweb (JSON, ou zlib quando
    # o SDK comprime)
    def self.decode_replay_recording(payload)
      meta, data = payload.split("\n", 2)
      events = begin
        JSON.parse(data.dup.force_encoding("UTF-8"))
      rescue JSON::ParserError
        JSON.parse(Zlib::Inflate.inflate(data))
      end
      { "meta" => JSON.parse(meta), "events" => events }
    end
  end

  class Store
    def initialize(dump_dir)
      @dump_dir = dump_dir
      # Numeração dos arquivos gravados: não volta a zero quando os testes
      # limpam o receptor, senão os arquivos se sobrescreveriam
      @dump_seq = 0
      @mutex = Mutex.new
      clear
      FileUtils.mkdir_p(dump_dir) if dump_dir
    end

    def clear
      @mutex.synchronize { @envelopes = []; @markers = []; @seq = 0 }
    end

    def add_envelope(token, headers, raw)
      @mutex.synchronize do
        @seq += 1
        parsed = EnvelopeParser.parse(raw)
        entry = { "seq" => @seq, "received_at" => Time.now.utc.iso8601(3), "token" => token, "headers" => headers }.merge(parsed)
        @envelopes << entry
        dump(entry, raw) if @dump_dir
        entry
      end
    end

    def add_marker(token, body)
      @mutex.synchronize { @markers << { "received_at" => Time.now.utc.iso8601(3), "token" => token, "body" => body } }
    end

    def to_h
      @mutex.synchronize { { "envelopes" => @envelopes, "markers" => @markers } }
    end

    private

    def dump(entry, raw)
      types = entry["items"].map { |i| i["type"] }.uniq.join("+")
      @dump_seq += 1
      File.binwrite(File.join(@dump_dir, format("%05d-%s.envelope", @dump_seq, types)), raw)
    end
  end

  # O mount_proc do WEBrick só aceita GET/POST/PUT (DELETE e OPTIONS davam 405)
  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, app)
      super(server)
      @app = app
    end

    %w[GET HEAD POST PUT DELETE OPTIONS].each do |metodo|
      define_method("do_#{metodo}") { |req, res| @app.call(req, res) }
    end
  end

  class App
    ENVELOPE_PATH = %r{\A/api/v2/requests/api/(?<token>[^/]+)/envelope/?\z}.freeze

    def initialize(store)
      @store = store
    end

    def call(req, res)
      cors(res)
      return if req.request_method == "OPTIONS"

      case [req.request_method, req.path]
      in ["GET", "/_saude"] then json(res, { ok: true })
      in ["GET", "/_recebidos"] then json(res, @store.to_h)
      in ["DELETE", "/_recebidos"] then @store.clear; json(res, { ok: true })
      in ["POST", "/api/requisicoes/markers"]
        @store.add_marker(req.query["token"], parse_json(req.body.to_s))
        json(res, { ok: true })
      in ["POST", path] if (m = ENVELOPE_PATH.match(path))
        raw = req.body.to_s
        raw = Zlib::GzipReader.new(StringIO.new(raw)).read if req["Content-Encoding"].to_s.include?("gzip")
        headers = { "content_type" => req["Content-Type"], "content_encoding" => req["Content-Encoding"], "user_agent" => req["User-Agent"], "origin" => req["Origin"] }
        @store.add_envelope(m[:token], headers, raw)
        json(res, { ok: true })
      else
        res.status = 404
        json(res, { erro: "rota desconhecida: #{req.request_method} #{req.path}" })
      end
    rescue StandardError => e
      warn "[receiver] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      res.status = 400
      json(res, { erro: "#{e.class}: #{e.message}" })
    end

    private

    def cors(res)
      res["Access-Control-Allow-Origin"] = "*"
      res["Access-Control-Allow-Headers"] = "*"
      res["Access-Control-Allow-Methods"] = "GET, POST, DELETE, OPTIONS"
    end

    def json(res, data)
      res["Content-Type"] = "application/json"
      res.body = JSON.generate(data)
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end

if $PROGRAM_NAME == __FILE__
  store = HaystackReceiver::Store.new(ENV["DUMP_DIR"])
  app = HaystackReceiver::App.new(store)
  server = WEBrick::HTTPServer.new(Port: Integer(ENV.fetch("PORT", 9292)), BindAddress: "0.0.0.0", AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN))
  server.mount("/", HaystackReceiver::Servlet, app)
  trap("TERM") { server.shutdown }
  trap("INT") { server.shutdown }
  server.start
end
