# frozen_string_literal: true

require "spec_helper"
require "haystack/rails/breadcrumb/active_support_logger"

# Até o Rails 7.0 o path dos eventos do controller vem com a query string crua;
# os breadcrumbs não podem levar os valores filtrados (achado pela suíte de
# integração: ?password=... aparecia no breadcrumb de process_action)
RSpec.describe "Breadcrumbs com parâmetros filtrados na URL", type: :request do
  let(:transport) { Haystack.get_current_client.transport }
  let(:breadcrumbs) { transport.events.first.to_json_compatible.dig("breadcrumbs", "values") }

  after do
    Haystack::Rails::Breadcrumb::ActiveSupportLogger.detach
    if defined?(Haystack::Rails::Breadcrumb::MonotonicActiveSupportLogger)
      Haystack::Rails::Breadcrumb::MonotonicActiveSupportLogger.detach
    end
    Haystack.get_current_scope.clear_breadcrumbs
  end

  %i[active_support_logger monotonic_active_support_logger].each do |logger|
    context "com #{logger}" do
      before do
        skip "monotonic_subscribe só existe a partir do Rails 6.1" if logger == :monotonic_active_support_logger && Rails.version.to_f < 6.1

        make_basic_app { |config| config.breadcrumbs_logger = [logger] }
      end

      it "filtra os valores sensíveis da query string e mantém os outros" do
        get "/exception?password=SenhaSecreta&busca=sapato&user%5Bsecret%5D=abc"

        paths = breadcrumbs.map { |b| b.dig("data", "path") }.compact
        expect(paths).not_to be_empty
        expect(paths.join).not_to include("SenhaSecreta", "abc")
        expect(paths).to all(eq("/exception?password=[FILTERED]&busca=sapato&user%5Bsecret%5D=[FILTERED]"))
      end
    end
  end

  describe "PathFilter" do
    subject(:described_class) { Haystack::Rails::Breadcrumb::PathFilter }

    before { make_basic_app }

    it "não mexe em paths sem query string" do
      expect(described_class.filter_data(path: "/pedidos/5")).to eq(path: "/pedidos/5")
    end

    it "mantém parâmetros sem valor" do
      expect(described_class.filter_path("/x?flag&password=1")).to eq("/x?flag&password=[FILTERED]")
    end
  end
end
