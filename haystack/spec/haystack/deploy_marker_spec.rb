# frozen_string_literal: true

require "spec_helper"
require "webrick"
require "rake"
require "haystack/deploy_marker"

RSpec.describe Haystack::DeployMarker do
  # Servidor HTTP de verdade no lugar do Farmer: registra o que recebe
  let(:received) { [] }
  let(:response_status) { 200 }
  let!(:server) do
    server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", AccessLog: [], Logger: WEBrick::Log.new(File::NULL))
    server.mount_proc("/") do |req, res|
      received << { path: req.path, query: req.query_string, content_type: req["Content-Type"], body: JSON.parse(req.body) }
      res.status = response_status
    end
    Thread.new { server.start }
    server
  end
  let(:port) { server.config[:Port] }
  let(:dsn) { "http://haystack@127.0.0.1:#{port}/api/v2/requests/token-do-projeto" }

  after { server.shutdown }

  it "envia revisão e usuário para /api/requisicoes/markers com o token da DSN" do
    result = described_class.notify(dsn: dsn, revision: "abc123", user: "pedro")

    expect(result).to be_ok
    expect(result.message).to eq("deploy abc123 registrado (pedro)")
    expect(received).to eq([{ path: "/api/requisicoes/markers", query: "token=token-do-projeto",
                              content_type: "application/json", body: { "revision" => "abc123", "user" => "pedro" } }])
  end

  it "aceita uma URL de marcadores diferente, mantendo o token da DSN" do
    described_class.notify(dsn: "http://haystack@outro-host.invalid/api/v2/requests/tk", revision: "r1", user: "u",
                           markers_url: "http://127.0.0.1:#{port}/outro/caminho")

    expect(received.first).to include(path: "/outro/caminho", query: "token=tk")
  end

  it "não envia nada sem DSN" do
    result = described_class.notify(dsn: nil, revision: "r1", user: "u")

    expect(result).not_to be_ok
    expect(result.message).to include("HAYSTACK_DSN não definido")
    expect(received).to be_empty
  end

  context "quando o Farmer responde com erro" do
    let(:response_status) { 404 }

    it "informa o status sem levantar exceção" do
      result = described_class.notify(dsn: dsn, revision: "r1", user: "u")

      expect(result).not_to be_ok
      expect(result.message).to eq("falha ao registrar o deploy: HTTP 404")
    end
  end

  it "não levanta exceção quando o Farmer está fora do ar (o deploy segue)" do
    free_port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    result = described_class.notify(dsn: "http://haystack@127.0.0.1:#{free_port}/api/v2/requests/tk", revision: "r1", user: "u",
                                    open_timeout: 1, read_timeout: 1)

    expect(result).not_to be_ok
    expect(result.message).to start_with("falha ao registrar o deploy:")
  end

  describe "task haystack:deploy (haystack/capistrano)" do
    # Simula o que o Capistrano oferece à task: o DSL do Rake e o fetch das variáveis
    let(:capistrano_settings) { { haystack_dsn: dsn, current_revision: "def456", haystack_user: "deployer" } }
    let(:main) { TOPLEVEL_BINDING.receiver }

    let(:hooks) { [] }

    before do
      settings = capistrano_settings
      registered = hooks
      main.define_singleton_method(:fetch) { |key, default = nil| settings.fetch(key, default) }
      main.define_singleton_method(:after) { |task, hook| registered << [task, hook] }
      Rake.application = Rake::Application.new
      main.extend(Rake::DSL)
      require "haystack/capistrano"
      load File.expand_path("../../lib/haystack/integrations/capistrano/haystack.cap", __dir__)
    end

    after do
      main.singleton_class.send(:remove_method, :fetch)
      main.singleton_class.send(:remove_method, :after)
      Rake.application = Rake::Application.new
    end

    it "se registra depois de deploy:finished, como no Haystack 0.x (os apps só fazem o require)" do
      expect(hooks).to include(["deploy:finished", "haystack:deploy"])
    end

    it "registra o deploy com a revisão atual" do
      expect { Rake::Task["haystack:deploy"].invoke }.to output(/deploy def456 registrado \(deployer\)/).to_stdout

      expect(received.first[:body]).to eq("revision" => "def456", "user" => "deployer")
    end

    context "sem DSN" do
      let(:capistrano_settings) { { current_revision: "def456" } }

      it "avisa e não falha" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("HAYSTACK_DSN").and_return(nil)

        expect { Rake::Task["haystack:deploy"].invoke }.to output(/HAYSTACK_DSN não definido/).to_stderr
        expect(received).to be_empty
      end
    end
  end
end
