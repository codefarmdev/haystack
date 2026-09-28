# frozen_string_literal: true

require "spec_helper"

# Como os apps da Codefarm tratam erros: rescue_from + Haystack.add_exception
# (API do Haystack 0.x) e página de erro renderizada
class PedidosHaystackController < ActionController::Base
  rescue_from ZeroDivisionError, with: :render_error

  def salvar
    session[:carrinho] = "3 itens"
    session[:secret] = "segredo-da-sessao"
    raise ZeroDivisionError, "falhou ao salvar" if params[:falhar]

    render html: "<html><head></head><body>ok</body></html>".html_safe
  end

  private

  def render_error(exception)
    Haystack.add_exception(exception)
    render html: "<html><head></head><body>Ops</body></html>".html_safe, status: 500
  end
end

RSpec.describe "Contexto da requisição (params, sessão, IP, memória)", type: :request do
  let(:transport) { Haystack.get_current_client.transport }
  let(:events) { transport.events }
  let(:error_event) { events.find { |e| e.is_a?(Haystack::ErrorEvent) } }
  let(:transaction_event) { events.find { |e| e.is_a?(Haystack::TransactionEvent) } }

  before do
    make_basic_app do |config, app|
      config.traces_sample_rate = 1.0
      app.routes.append { get "/pedidos/salvar", to: "pedidos_haystack#salvar" }
    end
  end

  def salvar(params = {})
    get "/pedidos/salvar", params: { id: "5", password: "senha-do-usuario" }.merge(params), headers: { "REMOTE_ADDR" => "10.1.2.3" }
  end

  describe "erro tratado no rescue_from com Haystack.add_exception" do
    # A primeira requisição grava a sessão (como um login); a segunda falha
    before do
      salvar
      transport.events.clear
      salvar(falhar: "1")
    end

    it "é enviado como erro, com a resposta marcada para o replay do navegador" do
      expect(response.status).to eq(500)
      expect(error_event.exception.values.last.type).to eq("ZeroDivisionError")
      expect(response.headers["X-Haystack-Event-Id"]).to eq(error_event.event_id)
    end

    it "leva os params filtrados, sem controller/action" do
      params = error_event.extra[:params]

      expect(params).to include("id" => "5", "password" => "[FILTERED]", "falhar" => "1")
      expect(params.keys).not_to include("controller", "action")
    end

    it "leva a sessão filtrada, sem o token CSRF" do
      session_data = error_event.extra[:session_data]

      expect(session_data).to include("carrinho" => "3 itens", "secret" => "[FILTERED]")
      expect(session_data).not_to have_key("_csrf_token")
    end

    it "leva o IP do cliente" do
      expect(error_event.extra[:client_ip]).to eq("10.1.2.3")
    end

    it "não vaza a senha em nenhum lugar do evento" do
      # As linhas de código dos frames mostram o código-fonte (inclusive deste
      # spec, que contém a senha literal); o resto do evento não pode ter o valor
      event = error_event.to_hash
      event[:exception][:values].each { |v| v[:stacktrace][:frames].each { |f| f.except!(:pre_context, :context_line, :post_context) } }

      expect(event.to_json).not_to include("senha-do-usuario", "segredo-da-sessao")
    end
  end

  describe "transação de uma requisição normal" do
    before { salvar }

    it "tem o nome Controller#action e o mesmo contexto" do
      expect(transaction_event.transaction).to eq("PedidosHaystackController#salvar")
      expect(transaction_event.extra[:params]).to include("password" => "[FILTERED]")
      expect(transaction_event.extra[:client_ip]).to eq("10.1.2.3")
    end

    it "grava o tempo de view no span do controller" do
      span = transaction_event.spans.find { |s| s[:op] == "view.process_action.action_controller" }

      expect(span[:data]).to have_key(:view_runtime)
    end

    it "não marca a resposta como erro" do
      expect(response.headers).not_to have_key("X-Haystack-Event-Id")
    end
  end

  describe "memória do processo" do
    it "é lida de /proc/self/statm (Linux)" do
      allow(File).to receive(:readable?).and_call_original
      allow(File).to receive(:readable?).with("/proc/self/statm").and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/proc/self/statm").and_return("100000 51200 3000 1 0 20000 0")

      salvar

      expect(transaction_event.extra[:memory_usage]).to eq(200.0)
    end

    it "fica de fora onde não há /proc (macOS)" do
      allow(File).to receive(:readable?).and_call_original
      allow(File).to receive(:readable?).with("/proc/self/statm").and_return(false)

      salvar

      expect(transaction_event.extra).not_to have_key(:memory_usage)
    end
  end
end

RSpec.describe Haystack::Rails do
  describe ".parameter_filter" do
    before { make_basic_app }

    it "usa o filter_parameters do app" do
      expect(described_class.parameter_filter.filter("password" => "x", "nome" => "y")).to eq("password" => "[FILTERED]", "nome" => "y")
    end

    it "funciona no Rails 5.2, onde só existe o filtro do ActionDispatch" do
      hide_const("ActiveSupport::ParameterFilter")
      stub_const("ActionDispatch::Http::ParameterFilter", Class.new do
        def initialize(filters)
          @filters = filters.map(&:to_s)
        end

        def filter(params)
          params.each_with_object({}) { |(k, v), h| h[k] = @filters.include?(k) ? "[FILTERED]" : v }
        end
      end)

      expect(described_class.parameter_filter.filter("password" => "x")).to eq("password" => "[FILTERED]")
    end
  end
end
