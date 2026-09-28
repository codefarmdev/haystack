# frozen_string_literal: true

require "spec_helper"

RSpec.describe Haystack::Rails::Middleware::Injector do
  HTML = "<html><head><title>Página</title></head><body><h1>Olá</h1></body></html>"
  EVENT_ID = "0123456789abcdef0123456789abcdef"

  # Corpo de resposta que registra se foi fechado (o Rails libera o lock do
  # reloader no close)
  class ClosableBody
    attr_reader :closed

    def initialize(html)
      @html = html
      @closed = false
    end

    def each
      yield @html
    end

    def body
      @html
    end

    def close
      @closed = true
    end
  end

  # O que o injector lê do controller: params, request e @current_user
  class FakeController
    attr_reader :params, :request

    def initialize(params:, current_user: nil, remote_ip: "10.0.0.7")
      @params = ActionController::Parameters.new(params)
      @request = Struct.new(:remote_ip).new(remote_ip)
      @current_user = current_user
    end
  end

  FakeUser = Struct.new(:id, :name, :email)

  let(:dsn) { "http://haystack@farmer.test/api/v2/requests/token-do-projeto" }
  let(:content_type) { "text/html; charset=utf-8" }
  let(:body) { ClosableBody.new(HTML) }
  let(:inner_status) { 200 }
  let(:inner_app) { ->(_env) { [inner_status, { "Content-Type" => content_type, "Content-Length" => HTML.bytesize.to_s }, body] } }
  let(:injector) { described_class.new(inner_app) }
  let(:env) { Rack::MockRequest.env_for("http://app.test/pagina") }
  let(:asset_pipeline) { true }

  before do
    make_basic_app do |config|
      config.dsn = dsn
      config.environment = "test"
      config.enabled_environments = %w[test]
    end
    allow(injector).to receive(:asset_pipeline?).and_return(asset_pipeline)
  end

  def call(request_env = env)
    status, headers, response = injector.call(request_env)
    html = +""
    response.each { |part| html << part }
    [status, headers, html]
  end

  def injected_script(html)
    html[/<script>\s*\(function \(\) \{.*?\}\)\(\);\s*<\/script>/m]
  end

  describe "injeção do SDK" do
    it "coloca o bundle e a inicialização antes do </head>" do
      _, _, html = call

      expect(html).to include('<script src="/haystack/bundle.tracing.replay.min.js"></script>')
      expect(html).to match(%r{HS\.init\(.*</script>\s*</head>}m)
      expect(html).to include(%("#{dsn}"))
      expect(html).to include("<h1>Olá</h1>")
    end

    context "com headers em minúsculas (Rack 3, página de erro estática do Rails 7.1+)" do
      let(:inner_app) { ->(_env) { [500, { "content-type" => "text/html; charset=utf-8", "content-length" => HTML.bytesize.to_s }, body] } }

      it "injeta e atualiza o content-length existente" do
        _, headers, html = call

        expect(html).to include("HS.init(")
        expect(headers["content-length"]).to eq(html.bytesize.to_s)
        expect(headers.keys.grep(/content-length/i).size).to eq(1)
      end
    end

    it "recalcula o Content-Length e fecha o corpo original" do
      _, headers, html = call

      expect(headers["Content-Length"]).to eq(html.bytesize.to_s)
      expect(body.closed).to eq(true)
    end

    it "inicializa uma vez só por página (Turbolinks roda o script de novo a cada visita)" do
      _, _, html = call

      expect(injected_script(html)).to include("if (!window.__haystackInitialized)")
    end

    context "com resposta que não é HTML" do
      let(:content_type) { "application/json" }

      it "não mexe no corpo" do
        _, headers, html = call

        expect(html).to eq(HTML)
        expect(headers["Content-Length"]).to eq(HTML.bytesize.to_s)
      end
    end

    it "não injeta quando a página não tem </head>" do
      allow(body).to receive(:body).and_return("<p>fragmento</p>")
      allow(body).to receive(:each).and_yield("<p>fragmento</p>")

      _, _, html = call

      expect(html).to eq("<p>fragmento</p>")
    end

    context "sem asset pipeline (app sem Sprockets)" do
      let(:asset_pipeline) { false }

      it "não injeta (o bundle não teria de onde ser servido)" do
        _, _, html = call

        expect(html).to eq(HTML)
      end
    end

    context "sem DSN" do
      let(:dsn) { nil }

      it "não injeta" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("HAYSTACK_DSN").and_return(nil)

        _, _, html = call

        expect(html).to eq(HTML)
      end
    end

    it "não injeta quando o Haystack está desligado neste ambiente" do
      Haystack.configuration.enabled_environments = %w[production]

      _, _, html = call

      expect(html).to eq(HTML)
    end

    it "nunca derruba a página quando a injeção falha" do
      allow(injector).to receive(:generate_script).and_raise("falhou")
      allow(Rails.logger).to receive(:warn)

      status, _, html = call

      expect(status).to eq(200)
      expect(html).to eq(HTML)
      expect(Rails.logger).to have_received(:warn).with(/falha ao injetar o SDK JS: RuntimeError: falhou/)
    end
  end

  describe "erro no backend (header X-Haystack-Event-Id)" do
    it "devolve o id do evento e avisa o SDK na própria página" do
      env[Haystack::Rack::CaptureExceptions::ERROR_EVENT_ID_KEY] = EVENT_ID

      _, headers, html = call

      expect(headers["X-Haystack-Event-Id"]).to eq(EVENT_ID)
      expect(injected_script(html)).to include(%(window.__haystackBackendError("#{EVENT_ID}")))
    end

    context "em resposta JSON (XHR/fetch)" do
      let(:content_type) { "application/json" }

      it "também devolve o header" do
        env[Haystack::Rack::CaptureExceptions::ERROR_EVENT_ID_KEY] = EVENT_ID

        _, headers, = call

        expect(headers["X-Haystack-Event-Id"]).to eq(EVENT_ID)
      end
    end

    it "ignora ids que não são de evento (32 hex)" do
      env[Haystack::Rack::CaptureExceptions::ERROR_EVENT_ID_KEY] = "<script>"

      _, headers, html = call

      expect(headers).not_to have_key("X-Haystack-Event-Id")
      expect(html).not_to include("__haystackBackendError(\"")
    end

    it "sem erro não há header" do
      _, headers, = call

      expect(headers).not_to have_key("X-Haystack-Event-Id")
    end

    it "lê o header nas respostas de XHR e fetch (visitas do Turbolinks)" do
      _, _, html = call
      script = injected_script(html)

      expect(script).to include("XMLHttpRequest.prototype.send")
      expect(script).to include("window.fetch")
      expect(script).to include('getResponseHeader("X-Haystack-Event-Id")')
    end
  end

  describe "replay" do
    it "grava só com erro por padrão, com os limites configurados e buffer síncrono" do
      Haystack.configuration.js.mutation_limit = 50_000
      Haystack.configuration.js.replay_after_error_seconds = 12

      script = injected_script(call.last)

      expect(script).to include("replaysSessionSampleRate: 0.0")
      expect(script).to include("replaysOnErrorSampleRate: 1.0")
      expect(script).to include("mutationLimit: 50000")
      expect(script).to include("useCompression: false")
      expect(script).to include("var afterErrorMs = 12000;")
      # Depois do stop, cancela o envio que o SDK agenda antes do buffer novo
      expect(script).to match(/r\.stop\(\)\)\.then\(function \(\) \{.*r\._replay\.cancelFlush\(\).*r\.startBuffering\(\)/m)
    end

    it "grava pelo menos 6 s depois do erro (o SDK descarta replays com menos de 5 s)" do
      Haystack.configuration.js.replay_after_error_seconds = 2

      expect(injected_script(call.last)).to include("var afterErrorMs = 6000;")
    end

    it "avalia as taxas em lambda a cada página" do
      rate = 0.0
      Haystack.configuration.js.replays_session_sample_rate = -> { rate }

      rate = 0.25
      expect(injected_script(call.last)).to include("replaysSessionSampleRate: 0.25")
    end

    it "não liga o replay quando as duas taxas são zero" do
      Haystack.configuration.js.replays_session_sample_rate = 0
      Haystack.configuration.js.replays_on_error_sample_rate = 0

      script = injected_script(call.last)

      expect(script).not_to include("replayIntegration")
      expect(script).to include("browserTracingIntegration")
    end

    it "usa os padrões quando a lambda da configuração falha" do
      Haystack.configuration.js.replays_on_error_sample_rate = -> { raise "banco fora" }
      allow(Rails.logger).to receive(:warn)

      script = injected_script(call.last)

      expect(script).to include("replaysOnErrorSampleRate: 1.0")
      expect(Rails.logger).to have_received(:warn).with(/configuração do replay indisponível/)
    end
  end

  describe "DSN do navegador" do
    let(:dsn) { "http://haystack@app.test/api/v2/requests/tk" }

    it "usa o protocolo e a porta da página quando a DSN aponta para o próprio host" do
      request_env = Rack::MockRequest.env_for("https://app.test:8443/pagina")

      script = injected_script(call(request_env).last)

      expect(script).to include('"https://haystack@app.test:8443/api/v2/requests/tk"')
    end

    it "usa a DSN do backend (config.dsn) quando não há config.js.dsn nem HAYSTACK_DSN" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("HAYSTACK_DSN").and_return(nil)
      Haystack.configuration.js.dsn = nil

      expect(injected_script(call.last)).to include('"http://haystack@app.test/api/v2/requests/tk"')
    end

    it "prefere config.js.dsn" do
      Haystack.configuration.js.dsn = "https://haystack@outro.test/api/v2/requests/tk2"

      expect(injected_script(call.last)).to include('"https://haystack@outro.test/api/v2/requests/tk2"')
    end
  end

  describe "contexto da página" do
    let(:user) { FakeUser.new(7, "Maria </script><script>alert(1)</script>", "maria@example.com") }
    let(:controller) do
      FakeController.new(
        current_user: user,
        params: { "controller" => "pedidos", "action" => "show", "id" => "5", "password" => "segredo",
                  "busca" => "</script><script>alert('xss')</script>", "filtroAvancado" => { "secret" => "x" } }
      )
    end

    before do
      env["action_controller.instance"] = controller
      env["rack.session"] = { "session_id" => "abc", "_csrf_token" => "token-csrf",
                              "warden.user.user.key" => [[7], "$2a$12$hash"], "devise_masquerade_user" => "3" }
      env["action_dispatch.request.flash_hash"] = ActionDispatch::Flash::FlashHash.new(notice: "Salvo", alert: nil)
    end

    let(:script) { injected_script(call.last) }

    it "manda os params filtrados, sem controller/action e com chaves em snake_case" do
      params = JSON.parse(script[/HS\.setContext\('request_params', (\{.*?\})\);/, 1])

      expect(params).to include("id" => "5", "password" => "[FILTERED]", "filtro_avancado" => { "secret" => "[FILTERED]" })
      expect(params).not_to have_key("controller")
      expect(script).not_to include("segredo")
    end

    it "não deixa um valor fechar o <script> (XSS)" do
      expect(script).not_to include("</script><script>alert")
      expect(script.scan("</script>").size).to eq(1)
    end

    it "manda o usuário atual" do
      expect(script).to include('"id":7')
      expect(script).to include('"email":"maria@example.com"')
      expect(script).to include('"ip_address":"10.0.0.7"')
    end

    it "manda só dados não sensíveis da sessão" do
      session = script[/HS\.setContext\('session', (.*?)\);/, 1]

      expect(session).to include('"session_id":"abc"', '"user_id":"7"', "devise_masquerade_user")
      expect(session).not_to include("token-csrf")
      expect(session).not_to include("$2a$12$hash")
    end

    it "manda as mensagens flash" do
      expect(script).to include(%(HS.setContext('flash_messages', {"notice":"Salvo"})))
    end
  end

  describe "app sem Sprockets (API ou só webpacker)" do
    it "sobe normalmente e não injeta o SDK" do
      # O app de teste não carrega o sprockets/railtie: antes o initializer do
      # engine fazia config.assets.precompile e o boot quebrava
      expect(Rails.application.config.respond_to?(:assets)).to eq(false)

      _, _, response = described_class.new(inner_app).call(env)
      html = +""
      response.each { |part| html << part }

      expect(html).to eq(HTML)
    end
  end
end
