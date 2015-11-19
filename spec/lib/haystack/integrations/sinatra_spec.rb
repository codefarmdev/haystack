require 'spec_helper'

begin
  require 'sinatra'
rescue LoadError
end

if defined?(::Sinatra)
  ENV['HAYSTACK_PUSH_API_KEY'] = 'key'
  require 'haystack/integrations/sinatra'

  describe "Sinatra integration" do
    context "logger" do
      subject { Haystack.logger }

      it { should be_a Logger }
    end

    context "config" do
      subject { Haystack.config }

      it { should be_a(Haystack::Config) }
    end

    context "agent" do
      subject { Haystack.agent }

      it { should be_a(Haystack::Agent) }
    end

    it "should have added the listener middleware" do
      Sinatra::Application.middleware.to_a.should include(
        [Haystack::Rack::Listener, [], nil]
      )
    end

    it "should have added the instrumentation middleware" do
      Sinatra::Application.middleware.to_a.should include(
        [Haystack::Rack::SinatraInstrumentation, [], nil]
      )
    end
  end
end
