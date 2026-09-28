# frozen_string_literal: true

# Cenários com o Chrome de verdade: SDK do navegador, replay de erro e a
# integração com o backend pelo header X-Haystack-Event-Id
RSpec.describe "Haystack no navegador (SDK JS + replay)" do
  SENHA_NAVEGADOR = "SenhaDoNavegador-7a6b5c"
  CARTAO_NAVEGADOR = "5555666677778888"

  # Tipos de evento do rrweb
  RRWEB_FULL_SNAPSHOT = 2
  RRWEB_INCREMENTAL = 3
  RRWEB_META = 4
  RRWEB_INPUT = 5 # data.source de um incremental

  def tipos_rrweb(eventos)
    eventos.map { |e| e["type"] }.uniq
  end

  # URLs que o replay registrou: href dos eventos meta e destinos de navegação
  def urls_do_replay(replay_id)
    metas = eventos_rrweb(replay_id).select { |e| e["type"] == RRWEB_META }.map { |e| e.dig("data", "href") }
    navegacoes = breadcrumbs_do_replay(replay_id).select { |b| b["category"] == "navigation" }.map { |b| b.dig("data", "to") }
    (metas + navegacoes).compact
  end

  describe "G. erros de JavaScript" do
    %w[turbo classico].each do |modo|
      it "(#{modo}) o pageload gera uma transação javascript" do
        visitar("/#{modo}")

        transacao = esperar_item("transaction", "transação pageload do navegador") do |t|
          t["platform"] == "javascript" && t.dig("contexts", "trace", "op") == "pageload"
        end
        expect(transacao["transaction"]).to eq "/#{modo}"
        expect(transacao.dig("request", "url")).to eq url_do_app("/#{modo}")
      end

      it "(#{modo}) erro de JS gera evento + replay (buffer) com snapshot; o replay para após replay_after_error_seconds e um erro novo abre outro replay" do
        visitar("/#{modo}")
        digitar("#campo", "antes do erro")
        sleep 1
        clicar("#erro-js")

        evento = esperar_evento_js(/funcaoQueNaoExiste/)
        expect(evento["transaction"] || evento.dig("request", "url")).to include("/#{modo}")
        segmento = esperar_replay_do_erro(evento["event_id"])
        instante_do_erro = Time.now
        replay_id = segmento[:replay_id]

        expect(segmento[:replay_type]).to eq "buffer"
        expect(segmento[:segment_id]).to eq 0
        expect(evento.dig("contexts", "replay", "replay_id") || evento.dig("tags", "replayId")).to eq replay_id
        expect(tipos_rrweb(segmento[:eventos])).to include(RRWEB_FULL_SNAPSHOT, RRWEB_META)
        # O buffer tem o que aconteceu antes do erro (a digitação)
        entradas = segmento[:eventos].select { |e| e["type"] == RRWEB_INCREMENTAL && e.dig("data", "source") == RRWEB_INPUT }
        expect(entradas).not_to be_empty

        # Depois de replay_after_error_seconds o replay é encerrado: atividade
        # nova não gera mais segmentos dele
        sleep_ate = instante_do_erro + Matriz.replay_apos_erro + 6
        sleep([sleep_ate - Time.now, 0].max)
        segmentos_antes = segmentos_do_replay(replay_id).size
        digitar("#campo", " depois do fim do replay")
        clicar("#botao-morto")
        sleep 7
        expect(segmentos_do_replay(replay_id).size).to eq(segmentos_antes),
          "o replay #{replay_id} continuou gravando depois de #{Matriz.replay_apos_erro}s"
        # O buffer novo não pode ser enviado sem erro. Com
        # replay_after_error_seconds = 5 (o mesmo intervalo de envio do SDK) o
        # stop corre contra o flush em andamento e o segmento 0 do replay novo
        # sai sozinho, sem erro, com eventos do replay anterior (ver README)
        orfaos = segmentos_replay.reject { |s| s[:replay_id] == replay_id }
        expect(orfaos).to be_empty,
          "replay enviado sem erro depois do fim do replay de erro: #{orfaos.map { |s| s.slice(:replay_id, :segment_id, :error_ids) }}"

        # Um erro novo (diferente: o dedupe do SDK descarta um erro idêntico ao
        # anterior) abre um replay novo
        clicar("#erro-js-2")
        evento2 = esperar_evento_js(/outraFuncaoQueNaoExiste/)
        segmento2 = esperar_replay_do_erro(evento2["event_id"])
        expect(segmento2[:replay_id]).not_to eq replay_id
        expect(segmento2[:replay_type]).to eq "buffer"
        expect(segmento2[:segment_id]).to eq 0
        expect(tipos_rrweb(segmento2[:eventos])).to include(RRWEB_FULL_SNAPSHOT)
      end
    end

    it "(turbo) com o cookie usuario, o erro de JS vai com o usuário do setUser injetado" do
      entrar_como(7)
      visitar("/turbo")
      expect(elemento("#usuario").text).to eq "usuario7@exemplo.com.br"
      clicar("#erro-js")

      evento = esperar_evento_js
      expect(evento["user"]).to include("id" => 7, "email" => "usuario7@exemplo.com.br", "username" => "Usuária 7")
    end

    it "(turbo) formulário no navegador: senha e cartão não aparecem em nenhum envelope (replay mascara os inputs)" do
      marca = nova_marca
      visitar("/turbo/formulario?marca=#{marca}")
      digitar("#nome", "Fulano")
      digitar("#password", SENHA_NAVEGADOR)
      digitar("#cartao", CARTAO_NAVEGADOR)
      sleep 1
      clicar("#erro-js")
      evento = esperar_evento_js
      esperar_replay_do_erro(evento["event_id"])

      # Envia o formulário com o replay ainda gravando
      clicar("#enviar")
      esperar_titulo("Recebido")
      esperar_transacao("PaginasController#enviar")
      sleep 3

      bruto = receptor.recebidos_brutos
      expect(bruto).not_to include(SENHA_NAVEGADOR), "a senha apareceu em: #{bruto[/.{0,300}#{SENHA_NAVEGADOR}.{0,100}/m]}"
      expect(bruto).not_to include(CARTAO_NAVEGADOR), "o cartão apareceu em: #{bruto[/.{0,300}#{CARTAO_NAVEGADOR}.{0,100}/m]}"
    end
  end

  describe "H. erro do backend numa navegação" do
    it "(turbo) visita Turbolinks com erro tratado (render) envia o replay com o que aconteceu antes, nas páginas anteriores" do
      marca = nova_marca
      visitar("/turbo?marca=#{marca}")
      js("window.__marcaDaCarga = 'primeira'")
      digitar("#campo", "texto antes do erro")
      clicar("#link-pagina2")
      esperar_titulo("Página 2")
      digitar("#campo2", "na página 2")
      sleep 1

      antes_do_erro = agora_ms
      clicar("#link-erro-render")
      esperar_titulo("Ops, ocorreu um erro")
      # Foram visitas Turbolinks (XHR): a página nunca recarregou
      expect(js("return window.__marcaDaCarga")).to eq "primeira"

      evento = esperar_evento_ruby(marca)
      segmento = esperar_replay_do_erro(evento["event_id"])
      replay_id = segmento[:replay_id]
      expect(segmento[:replay_type]).to eq "buffer"

      eventos = eventos_rrweb(replay_id)
      anteriores = eventos.select { |e| e["timestamp"].to_i < antes_do_erro }
      expect(anteriores).not_to be_empty, "o replay não tem nada anterior ao erro"
      expect(tipos_rrweb(anteriores)).to include(RRWEB_FULL_SNAPSHOT)
      entradas = anteriores.select { |e| e["type"] == RRWEB_INCREMENTAL && e.dig("data", "source") == RRWEB_INPUT }
      expect(entradas).not_to be_empty, "o replay não tem a digitação anterior ao erro"
      expect(urls_do_replay(replay_id)).to include(a_string_including("/turbo?marca=#{marca}"), a_string_including("/turbo/pagina2"))
    end

    it "(classico) erro tratado (render) em página inteira: o replay da página de erro leva o id do evento" do
      marca = nova_marca
      visitar("/classico?marca=#{marca}")
      digitar("#campo", "texto antes do erro")
      clicar("#link-erro-render")
      esperar_titulo("Ops, ocorreu um erro")

      evento = esperar_evento_ruby(marca)
      segmento = esperar_replay_do_erro(evento["event_id"])
      expect(segmento[:replay_type]).to eq "buffer"
      expect(urls_do_replay(segmento[:replay_id])).to include(a_string_including("/classico/erro-render"))
    end
  end

  describe "I. limitação conhecida: erro tratado com redirect" do
    # O header X-Haystack-Event-Id fica no 302; o navegador (ou o XHR do
    # Turbolinks, que segue o redirect sozinho) nunca o expõe ao JS, e a página
    # de destino é outra requisição, sem erro capturado. O evento chega, mas não
    # é ligado a nenhum replay.
    %w[classico turbo].each do |modo|
      it "(#{modo}) LIMITAÇÃO CONHECIDA: o evento do backend chega, mas nenhum replay contém o id dele" do
        marca = nova_marca
        visitar("/#{modo}?marca=#{marca}")
        digitar("#campo", "texto antes do erro")
        clicar("#link-erro-redirect")
        esperar_titulo("Ops, ocorreu um erro")

        evento = esperar_evento_ruby(marca)
        expect(excecao(evento)["value"]).to include("Erro tratado com redirect (#{marca})")
        # Tempo para qualquer replay que fosse chegar
        sleep 10

        expect(segmentos_replay.flat_map { |s| s[:error_ids] }).not_to include(evento["event_id"])
      end
    end
  end

  describe "J. cliques mortos e repetidos" do
    it "(turbo) cliques repetidos no botão morto geram ui.slowClickDetected (rage click) no replay" do
      visitar("/turbo")
      sleep 1
      6.times { clicar("#botao-morto") }
      # O SDK só declara o clique "morto" depois de 7 s sem reação da página
      sleep 9
      clicar("#erro-js")

      evento = esperar_evento_js
      segmento = esperar_replay_do_erro(evento["event_id"])
      breadcrumbs = breadcrumbs_do_replay(segmento[:replay_id])
      categorias = breadcrumbs.map { |b| b["category"] }
      expect(categorias).to include("ui.click")

      # Cliques repetidos no mesmo elemento sem reação viram um único
      # ui.slowClickDetected com clickCount >= 3 (rage click); neste cenário o
      # SDK não gera ui.multiClick
      lento = breadcrumbs.find { |b| b["category"] == "ui.slowClickDetected" }
      expect(lento).not_to be_nil, "sem ui.slowClickDetected; breadcrumbs: #{categorias}"
      expect(lento["message"]).to include("button#botao-morto")
      expect(lento.dig("data", "clickCount")).to be >= 3
      expect(lento.dig("data", "endReason")).to eq "timeout"
    end
  end
end
