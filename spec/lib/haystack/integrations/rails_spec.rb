require 'spec_helper'

if rails_present?
  describe Haystack::Integrations::Railtie do
    context "after initializing the app" do
      it "should call initialize_haystack" do
        expect( Haystack::Integrations::Railtie ).to receive(:initialize_haystack)

        MyApp::Application.config.root = project_fixture_path
        MyApp::Application.initialize!
      end
    end

    describe "#initialize_haystack" do
      let(:app) { MyApp::Application }
      before { app.middleware.stub(:insert_before => true) }

      context "logger" do
        before  { Haystack::Integrations::Railtie.initialize_haystack(app) }
        subject { Haystack.logger }

        it { should be_a Logger }
      end

      context "config" do
        before  { Haystack::Integrations::Railtie.initialize_haystack(app) }
        subject { Haystack.config }

        it { should be_a(Haystack::Config) }

        its(:root_path) { should == Pathname.new(project_fixture_path) }
        its(:env)       { should == 'test' }
        its([:name])    { should == 'TestApp' }

        context "initial config" do
          before  { Haystack::Integrations::Railtie.initialize_haystack(app) }
          subject { Haystack.config.initial_config }

          its([:name]) { should == 'MyApp' }
        end

        context "with HAYSTACK_APP_ENV ENV var set" do
          around do |sample|
            ENV['HAYSTACK_APP_ENV'] = 'env_test'
            sample.run
            ENV.delete('HAYSTACK_APP_ENV')
          end


          its(:env) { should == 'env_test' }
        end
      end

      context "agent" do
        before  { Haystack::Integrations::Railtie.initialize_haystack(app) }
        subject { Haystack.agent }

        it { should be_a(Haystack::Agent) }
      end

      context "listener middleware" do
        it "should have added the listener middleware" do
          expect( app.middleware ).to receive(:insert_before).with(
            ActionDispatch::RemoteIp,
            Haystack::Rack::Listener
          )
        end

        context "when frontend_error_catching is enabled" do
          let(:config) do
            Haystack::Config.new(
              project_fixture_path,
              'test',
              :name => 'MyApp',
              :enable_frontend_error_catching => true
            )
          end

          before do
            Haystack.stub(:config => config)
          end

          it "should have added the listener and JSExceptionCatcher middleware" do
            expect( app.middleware ).to receive(:insert_before).with(
              ActionDispatch::RemoteIp,
              Haystack::Rack::Listener
            )

            expect( app.middleware ).to receive(:insert_before).with(
              Haystack::Rack::Listener,
              Haystack::Rack::JSExceptionCatcher
            )
          end
        end

        after { Haystack::Integrations::Railtie.initialize_haystack(app) }
      end
    end
  end
end
