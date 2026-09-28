# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Cliente do receptor (Farmer falso, integration/receiver/receiver.rb)
class Receptor
  attr_reader :url

  def initialize(url)
    @url = url.chomp("/")
  end

  def saudavel?
    requisitar(Net::HTTP::Get.new("/_saude")).is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  # Tudo o que chegou, como devolvido por GET /_recebidos
  def recebidos
    JSON.parse(requisitar(Net::HTTP::Get.new("/_recebidos")).body)
  end

  # Corpo cru de GET /_recebidos: usado para procurar valores em qualquer
  # parte de qualquer envelope
  def recebidos_brutos
    requisitar(Net::HTTP::Get.new("/_recebidos")).body
  end

  def envelopes
    recebidos.fetch("envelopes")
  end

  def limpar
    resposta = requisitar(Net::HTTP::Delete.new("/_recebidos"))
    raise "falha ao limpar o receptor: HTTP #{resposta.code}" unless resposta.is_a?(Net::HTTPSuccess)
  end

  private

  def requisitar(requisicao)
    uri = URI(@url)
    resposta = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 20) { |http| http.request(requisicao) }
    resposta.body&.force_encoding(Encoding::UTF_8)
    resposta
  end
end

# Métodos de espera/busca usados pelos testes (incluídos nos exemplos)
module AjudaReceptor
  class TempoEsgotado < StandardError; end

  def receptor
    @receptor ||= Receptor.new(ENV.fetch("RECEIVER_URL", "http://receiver:9292"))
  end

  # Repete o bloco até ele devolver algo "verdadeiro" ou o tempo acabar
  def esperar_ate(descricao, timeout: 20, intervalo: 0.3)
    limite = Time.now + timeout
    loop do
      resultado = yield
      return resultado if resultado
      raise TempoEsgotado, "#{descricao}: nada em #{timeout}s. Recebido até agora: #{resumo_recebidos}" if Time.now > limite

      sleep intervalo
    end
  end

  # Espera um envelope que satisfaça o bloco
  def wait_for_envelope(timeout = 20, &bloco)
    esperar_ate("envelope", timeout: timeout) { receptor.envelopes.find(&bloco) }
  end
  alias esperar_envelope wait_for_envelope

  # Payloads de todos os itens de um tipo (event, transaction, replay_event...)
  def itens(tipo)
    receptor.envelopes.flat_map { |env| env["items"].select { |i| i["type"] == tipo }.map { |i| i["payload"] } }
  end

  def esperar_item(tipo, descricao = tipo, timeout: 20, &bloco)
    bloco ||= ->(_) { true }
    esperar_ate(descricao, timeout: timeout) { itens(tipo).find(&bloco) }
  end

  def excecao(evento)
    Array(evento.dig("exception", "values")).last || {}
  end

  def eventos_ruby
    itens("event").select { |e| e["platform"] == "ruby" }
  end

  def eventos_js
    itens("event").select { |e| e["platform"] == "javascript" }
  end

  # Evento de erro do backend cuja mensagem contém a marca do teste
  def esperar_evento_ruby(marca, timeout: 20)
    esperar_ate("evento ruby com a marca #{marca}", timeout: timeout) do
      eventos_ruby.find { |e| excecao(e)["value"].to_s.include?(marca) }
    end
  end

  def esperar_evento_js(padrao = /funcaoQueNaoExiste/, excluir: [], timeout: 20)
    esperar_ate("evento javascript #{padrao.inspect}", timeout: timeout) do
      eventos_js.find { |e| excecao(e)["value"].to_s.match?(padrao) && !excluir.include?(e["event_id"]) }
    end
  end

  def transacoes(nome = nil)
    lista = itens("transaction")
    nome ? lista.select { |t| t["transaction"] == nome } : lista
  end

  def esperar_transacao(nome, timeout: 20, &bloco)
    bloco ||= ->(_) { true }
    esperar_ate("transação #{nome}", timeout: timeout) { transacoes(nome).find(&bloco) }
  end

  # Segmentos de replay: cada envelope de replay tem um replay_event e um
  # replay_recording (eventos rrweb daquele segmento)
  def segmentos_replay
    receptor.envelopes.filter_map do |env|
      evento = env["items"].find { |i| i["type"] == "replay_event" }
      next unless evento

      gravacao = env["items"].find { |i| i["type"] == "replay_recording" }
      p = evento["payload"]
      {
        replay_id: p["replay_id"],
        segment_id: p["segment_id"],
        replay_type: p["replay_type"],
        error_ids: Array(p["error_ids"]),
        trace_ids: Array(p["trace_ids"]),
        urls: Array(p["urls"]),
        eventos: gravacao ? Array(gravacao.dig("payload", "events")) : [],
        recebido_em: env["received_at"],
        seq: env["seq"]
      }
    end
  end

  def segmentos_do_replay(replay_id)
    segmentos_replay.select { |s| s[:replay_id] == replay_id }.sort_by { |s| s[:segment_id] }
  end

  # Segmento de replay cujo error_ids contém o id do evento
  def esperar_replay_do_erro(event_id, timeout: 25)
    esperar_ate("replay com error_ids contendo #{event_id}", timeout: timeout) do
      segmentos_replay.find { |s| s[:error_ids].include?(event_id) }
    end
  end

  # Todos os eventos rrweb recebidos de um replay, em ordem de segmento
  def eventos_rrweb(replay_id)
    segmentos_do_replay(replay_id).flat_map { |s| s[:eventos] }
  end

  # Breadcrumbs que o SDK grava dentro do replay (evento rrweb custom, tipo 5)
  def breadcrumbs_do_replay(replay_id)
    eventos_rrweb(replay_id)
      .select { |e| e["type"] == 5 && e.dig("data", "tag") == "breadcrumb" }
      .map { |e| e.dig("data", "payload") }
  end

  def resumo_recebidos
    tipos = receptor.envelopes.map { |env| env["items"].map { |i| i["type"] }.join("+") }
    tipos.tally.map { |t, n| "#{t} x#{n}" }.join(", ").then { |s| s.empty? ? "(nada)" : s }
  rescue StandardError => e
    "(receptor indisponível: #{e.message})"
  end
end
