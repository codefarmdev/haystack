# frozen_string_literal: true

# Cenários só de backend: requisições HTTP diretas ao app, sem navegador
RSpec.describe "Haystack no backend (Rails)" do
  BUNDLE_REGEX = %r{<script src="(/assets/haystack/bundle\.tracing\.replay\.min-[0-9a-f]{32,}\.js)"></script>}
  DSN_ESPERADA = "http://haystack@receiver:9292/api/v2/requests/token-integracao"
  SENHA = "SenhaSecreta-9f8e7d"
  CARTAO = "4111222233334444"

  describe "A. boot e assets" do
    %w[turbo classico].each do |modo|
      it "(#{modo}) a página HTML traz o bundle precompilado com digest e o script de init antes do </head>" do
        resposta = http_get("/#{modo}")
        expect(resposta.code).to eq "200"
        corpo = resposta.body

        expect(corpo).to match(BUNDLE_REGEX)
        expect(corpo).to include("window.__haystackInitialized", "HS.init(", DSN_ESPERADA.to_json)
        expect(corpo).to include("var afterErrorMs = #{Matriz.replay_apos_erro * 1000};")
        expect(corpo.index(BUNDLE_REGEX)).to be < corpo.index("</head>")
        expect(resposta["X-Haystack-Event-Id"]).to be_nil
      end
    end

    it "o bundle com digest é servido com 200 como JavaScript" do
      caminho = http_get("/turbo").body[BUNDLE_REGEX, 1]
      asset = http_get(caminho)

      expect(asset.code).to eq "200"
      expect(asset["Content-Type"]).to include("javascript")
      expect(asset.body.bytesize).to be > 100_000
      expect(asset.body).to include("replayIntegration")
    end

    it "o caminho sem digest não existe em produção (por isso o injector usa asset_path)" do
      expect(http_get("/assets/haystack/bundle.tracing.replay.min.js").code).to eq "404"
    end

    it "respostas JSON não recebem o script" do
      resposta = http_get("/turbo/api/ok.json")

      expect(resposta.code).to eq "200"
      expect(resposta["Content-Type"]).to include("application/json")
      expect(JSON.parse(resposta.body)).to eq("ok" => true, "modo" => "turbo")
      expect(resposta.body).not_to include("<script")
    end
  end

  describe "B. erro não tratado" do
    %w[turbo classico].each do |modo|
      it "(#{modo}) vira evento ruby com exceção, stacktrace do app, request e o header X-Haystack-Event-Id" do
        marca = nova_marca
        resposta = http_get("/#{modo}/erro?marca=#{marca}")

        expect(resposta.code).to eq "500"
        event_id = resposta["X-Haystack-Event-Id"]
        expect(event_id).to match(/\A\h{32}\z/)
        expect(resposta.body).to include("Erro 500")

        evento = esperar_evento_ruby(marca)
        expect(evento["event_id"]).to eq event_id
        expect(evento["platform"]).to eq "ruby"
        expect(evento["level"]).to eq "error"
        expect(evento["environment"]).to eq "production"
        expect(evento["transaction"]).to eq "ErrosController#nao_tratado"

        ex = excecao(evento)
        expect(ex["type"]).to eq "ErroDeIntegracao"
        expect(ex["value"]).to include("Erro não tratado (#{marca})")
        frames = ex.dig("stacktrace", "frames")
        frame_do_app = frames.find { |f| f["filename"].to_s.include?("app/controllers/erros_controller.rb") }
        expect(frame_do_app).not_to be_nil, "nenhum frame do app em #{frames.map { |f| f['filename'] }.last(5)}"
        expect(frame_do_app).to include("in_app" => true, "function" => "nao_tratado")
        expect(frame_do_app["lineno"]).to be_a(Integer)

        expect(evento.dig("request", "url")).to eq url_do_app("/#{modo}/erro")
        expect(evento.dig("request", "method")).to eq "GET"
        expect(evento.dig("contexts", "trace", "trace_id")).to match(/\A\h{32}\z/)

        envelope = esperar_envelope { |env| env.dig("header", "event_id") == event_id }
        expect(envelope["token"]).to eq "token-integracao"
        expect(envelope.dig("header", "sdk", "name")).to eq "haystack.ruby"
      end
    end

    %w[turbo classico].each do |modo|
      it "(#{modo}) a página 500 estática do Rails (public/500.html) recebe o script, já avisando do erro" do
        # No Rails >= 7.1 (Rack 3) o ActionDispatch::PublicExceptions devolve os
        # headers num Hash comum com "content-type" minúsculo (corrigido no 1.1.0:
        # antes a página 500 ficava sem o SDK)
        resposta = http_get("/#{modo}/erro?marca=#{nova_marca}")
        event_id = resposta["X-Haystack-Event-Id"]

        expect(resposta.code).to eq "500"
        expect(event_id).to match(/\A\h{32}\z/)
        expect(resposta.body).to include("Erro 500", "window.__haystackInitialized", "window.__haystackBackendError(#{event_id.to_json})")
      end
    end

    it "erro num endpoint JSON: evento ruby, header presente e corpo JSON sem script" do
      marca = nova_marca
      resposta = http_get("/turbo/api/erro.json?marca=#{marca}")

      expect(resposta.code).to eq "500"
      expect(resposta["Content-Type"]).to include("application/json")
      expect(resposta.body).not_to include("<script")
      expect { JSON.parse(resposta.body) }.not_to raise_error

      evento = esperar_evento_ruby(marca)
      expect(resposta["X-Haystack-Event-Id"]).to eq evento["event_id"]
      expect(excecao(evento)["value"]).to include("Erro na API (#{marca})")
      expect(evento["transaction"]).to eq "ErrosController#api_erro"
    end
  end

  describe "C. erro tratado no controller (rescue_from + Haystack.add_exception)" do
    %w[turbo classico].each do |modo|
      it "(#{modo}) com render da página de erro: evento chega e a resposta 500 tem o header" do
        marca = nova_marca
        resposta = http_get("/#{modo}/erro-render?marca=#{marca}")

        expect(resposta.code).to eq "500"
        expect(resposta.body).to include("Ops, ocorreu um erro")
        event_id = resposta["X-Haystack-Event-Id"]
        expect(event_id).to match(/\A\h{32}\z/)
        expect(resposta.body).to include("window.__haystackBackendError(#{event_id.to_json})")

        evento = esperar_evento_ruby(marca)
        expect(evento["event_id"]).to eq event_id
        expect(excecao(evento)["type"]).to eq "ErroDeIntegracao"
        expect(excecao(evento)["value"]).to include("Erro tratado com render (#{marca})")
        expect(evento["transaction"]).to eq "ErrosRenderController#show"
      end

      it "(#{modo}) com redirect: evento chega e o header está no 302 (a página de destino não o tem)" do
        marca = nova_marca
        resposta = http_get("/#{modo}/erro-redirect?marca=#{marca}")

        expect(resposta.code).to eq "302"
        expect(resposta["Location"]).to eq url_do_app("/#{modo}/erro-servidor?marca=#{marca}")
        event_id = resposta["X-Haystack-Event-Id"]
        expect(event_id).to match(/\A\h{32}\z/)

        evento = esperar_evento_ruby(marca)
        expect(evento["event_id"]).to eq event_id
        expect(excecao(evento)["value"]).to include("Erro tratado com redirect (#{marca})")

        destino = http_get(URI(resposta["Location"]).request_uri)
        expect(destino.code).to eq "500"
        expect(destino["X-Haystack-Event-Id"]).to be_nil
        expect(destino.body).not_to include("window.__haystackBackendError(")
      end
    end
  end

  describe "D. filtro de parâmetros (password, cartao)" do
    def expect_sem_segredos!
      # Dá tempo de chegarem as transações e demais envelopes da requisição
      sleep 1.5
      bruto = receptor.recebidos_brutos
      expect(bruto).not_to include(SENHA), "a senha apareceu em: #{bruto[/.{0,300}#{SENHA}.{0,100}/m]}"
      expect(bruto).not_to include(CARTAO), "o cartão apareceu em: #{bruto[/.{0,300}#{CARTAO}.{0,100}/m]}"
    end

    it "erro com os valores na query string: aparecem como [FILTERED] e em nenhum lugar dos envelopes" do
      # Até o Rails 7.0 os breadcrumbs start_processing/process_action recebem
      # payload[:path] = request.fullpath, com a query string sem filtro
      # (corrigido no 1.1.0: o haystack-rails filtra o path dos breadcrumbs)
      marca = nova_marca
      resposta = http_get("/turbo/erro?marca=#{marca}&password=#{SENHA}&cartao=#{CARTAO}&nome=Fulano")
      expect(resposta.body).not_to include(SENHA, CARTAO)

      evento = esperar_evento_ruby(marca)
      expect(evento.dig("extra", "params")).to include("password" => "[FILTERED]", "cartao" => "[FILTERED]", "nome" => "Fulano")
      esperar_transacao("ErrosController#nao_tratado")

      expect_sem_segredos!
    end

    it "os eventos e transações em si (sem breadcrumbs) não levam os valores" do
      marca = nova_marca
      http_get("/turbo/erro?marca=#{marca}&password=#{SENHA}&cartao=#{CARTAO}")
      evento = esperar_evento_ruby(marca)
      transacao = esperar_transacao("ErrosController#nao_tratado")

      [evento, transacao].each do |payload|
        sem_breadcrumbs = JSON.generate(payload.reject { |k, _| k == "breadcrumbs" })
        expect(sem_breadcrumbs).not_to include(SENHA)
        expect(sem_breadcrumbs).not_to include(CARTAO)
      end
      expect(evento.dig("request", "query_string").to_s).not_to include(SENHA)
    end

    it "POST do formulário: transação com [FILTERED] e o script injetado sem os valores" do
      marca = nova_marca
      formulario = http_get("/classico/formulario?marca=#{marca}")
      cookies = cookies_da_resposta(formulario)
      resposta = http_post_form(
        "/classico/formulario?marca=#{marca}",
        { "authenticity_token" => token_csrf(formulario.body), "nome" => "Fulano", "password" => SENHA, "cartao" => CARTAO },
        cookies: cookies
      )

      expect(resposta.code).to eq "200"
      expect(resposta.body).to include("Obrigado, Fulano")
      expect(resposta.body).not_to include(SENHA, CARTAO)
      # request_params do script injetado passam pelo mesmo filtro
      expect(resposta.body).to include('"password":"[FILTERED]"', '"cartao":"[FILTERED]"')

      transacao = esperar_transacao("PaginasController#enviar")
      expect(transacao.dig("extra", "params")).to include("password" => "[FILTERED]", "cartao" => "[FILTERED]", "nome" => "Fulano")

      expect_sem_segredos!
    end
  end

  describe "E. contexto do usuário" do
    it "com o cookie usuario, o evento traz id/email e o script injetado chama setUser" do
      marca = nova_marca
      resposta = http_get("/turbo/erro-render?marca=#{marca}", cookies: { "usuario" => "42" })

      evento = esperar_evento_ruby(marca)
      expect(evento["user"]).to include("id" => 42, "email" => "usuario42@exemplo.com.br", "username" => "Usuária 42")

      argumento = resposta.body[/HS\.setUser\((\{.*?\})\);/, 1]
      expect(argumento).not_to be_nil, "setUser com usuário não encontrado no HTML"
      expect(JSON.parse(argumento)).to include("id" => 42, "email" => "usuario42@exemplo.com.br", "username" => "Usuária 42")
    end

    it "sem o cookie, o evento não herda o usuário de uma requisição anterior" do
      marca_com = nova_marca
      marca_sem = nova_marca
      http_get("/turbo/erro-render?marca=#{marca_com}", cookies: { "usuario" => "42" })
      esperar_evento_ruby(marca_com)
      resposta = http_get("/turbo/erro-render?marca=#{marca_sem}")

      evento = esperar_evento_ruby(marca_sem)
      expect(evento["user"].to_h["id"]).to be_nil
      expect(evento["user"].to_h["email"]).to be_nil
      expect(resposta.body).to include("HS.setUser(null);")
    end
  end

  describe "F. transações e demais integrações" do
    %w[turbo classico].each do |modo|
      it "(#{modo}) página normal gera a transação Controller#action com spans e os extras do fork" do
        marca = nova_marca
        expect(http_get("/#{modo}/pagina2?marca=#{marca}&password=#{SENHA}").code).to eq "200"

        transacao = esperar_transacao("PaginasController#pagina2") { |t| t.dig("extra", "params", "marca") == marca }
        expect(transacao.dig("contexts", "trace", "op")).to eq "http.server"
        expect(transacao.dig("contexts", "trace", "status")).to eq "ok"
        expect(transacao["platform"]).to eq "ruby"

        spans = transacao["spans"]
        ops = spans.map { |s| s["op"] }
        expect(ops).to include("view.process_action.action_controller")
        expect(ops).to include(a_string_starting_with("template.render"))
        acao = spans.find { |s| s["op"] == "view.process_action.action_controller" }
        expect(acao["description"]).to eq "PaginasController#pagina2"
        expect(acao.dig("data", "view_runtime")).to be_a(Numeric)
        expect(acao.dig("data", "params", "password")).to eq "[FILTERED]"
        expect(acao.dig("data", "path")).not_to include(SENHA)

        extra = transacao["extra"]
        expect(extra["params"]).to include("marca" => marca, "modo" => modo, "password" => "[FILTERED]")
        expect(extra["params"]).not_to include("controller", "action")
        expect(extra["session_data"]).to be_a(Hash)
        expect(extra["client_ip"]).to match(/\A[\d.:a-f]+\z/)
        expect(extra["memory_usage"]).to be_a(Numeric).and be > 0
      end
    end

    it "/saude não gera transação (traces_sampler)" do
      3.times { expect(http_get("/saude").code).to eq "200" }
      marca = nova_marca
      http_get("/turbo/pagina2?marca=#{marca}")
      esperar_transacao("PaginasController#pagina2")
      sleep 1

      expect(transacoes.map { |t| t["transaction"] }).not_to include("SaudeController#show")
    end

    it "exceção listada em excluded_exceptions (ErroIgnorado) não gera evento nem header" do
      marca_ignorada = nova_marca
      resposta = http_get("/turbo/erro-ignorado?marca=#{marca_ignorada}")
      expect(resposta.code).to eq "500"
      expect(resposta["X-Haystack-Event-Id"]).to be_nil

      # Um erro normal depois serve de marcador de que os envios já aconteceram
      marca = nova_marca
      http_get("/turbo/erro?marca=#{marca}")
      esperar_evento_ruby(marca)
      sleep 1

      expect(eventos_ruby.map { |e| excecao(e)["type"] }).not_to include("ErroIgnorado")
      expect(receptor.recebidos_brutos).not_to include("Erro ignorado (#{marca_ignorada})")
    end

    it "erro num ActiveJob (adapter async) gera evento com o contexto do job" do
      marca = nova_marca
      expect(http_get("/turbo/job?marca=#{marca}").code).to eq "200"

      evento = esperar_evento_ruby(marca)
      expect(excecao(evento)).to include("type" => "JobQueFalha::Falha", "module" => "JobQueFalha")
      expect(excecao(evento)["value"]).to include("Falha no job de integração (#{marca})")
      expect(evento.dig("extra", "active_job")).to eq "JobQueFalha"
      expect(evento.dig("extra", "arguments")).to eq [marca]
      expect(evento["transaction"]).to eq "JobQueFalha"

      transacao = esperar_transacao("JobQueFalha")
      expect(transacao.dig("contexts", "trace", "op")).to eq "queue.active_job"
    end
  end
end
