require 'spec_helper'

if capistrano3_present?
  require 'capistrano/all'
  require 'capistrano/deploy'
  require 'haystack/capistrano'

  include Capistrano::DSL

  describe "Capistrano 3 integration" do
    let(:config) { project_fixture_config }
    let(:io) { StringIO.new }
    let(:logger) { Logger.new(io) }

    before do
      @capistrano_config = Capistrano::Configuration.env
      @capistrano_config.set(:log_level, :error)
      @capistrano_config.set(:logger, logger)
    end
    before do
      @original_stderr = $stderr
      $stderr = io
    end
    after do
      $stderr = @original_stderr
      Rake::Task['haystack:deploy'].reenable
    end

    it "should have a deploy task" do
      Rake::Task.task_defined?('haystack:deploy').should be_true
    end

    describe "haystack:deploy task" do
      before do
        @capistrano_config.set(:rails_env, 'production')
        @capistrano_config.set(:repository, 'master')
        @capistrano_config.set(:deploy_to, '/home/username/app')
        @capistrano_config.set(:current_release, '')
        @capistrano_config.set(:current_revision, '503ce0923ed177a3ce000005')
        ENV['USER'] = 'batman'
        ENV['PWD'] = project_fixture_path
      end

      context "config" do
        it "should be instantiated with the right params" do
          Haystack::Config.should_receive(:new).with(
            project_fixture_path,
            'production',
            {},
            kind_of(Logger)
          )
        end

        context "when haystack_config is available" do
          before do
            @capistrano_config.set(:haystack_config, :name => 'AppName')
          end

          it "should be instantiated with the right params" do
            Haystack::Config.should_receive(:new).with(
              project_fixture_path,
              'production',
              {:name => 'AppName'},
              kind_of(Logger)
            )
          end

          context "when rack_env is used instead of rails_env" do
            before do
              @capistrano_config.delete(:rails_env)
              @capistrano_config.set(:rack_env, 'rack_production')
            end

            it "should be instantiated with the right params" do
              Haystack::Config.should_receive(:new).with(
                project_fixture_path,
                'rack_production',
                {:name => 'AppName'},
                kind_of(Logger)
              )
            end
          end
        end

        after { invoke('haystack:deploy') }
      end

      context "send marker" do
        let(:marker_data) do
          {
            :revision => '503ce0923ed177a3ce000005',
            :user => 'batman'
          }
        end

        context "when active for this environment" do
          before do
            @marker = Haystack::Marker.new(
              marker_data,
              config,
              logger
            )
            Haystack::Marker.stub(:new => @marker)
          end

          context "proper setup" do
            before do
              @transmitter = double
              Haystack::Transmitter.should_receive(:new).and_return(@transmitter)
            end

            it "should add the correct marker data" do
              Haystack::Marker.should_receive(:new).with(
                marker_data,
                kind_of(Haystack::Config),
                kind_of(Logger)
              ).and_return(@marker)

              invoke('haystack:deploy')
            end

            it "should transmit data" do
              @transmitter.should_receive(:transmit).and_return('200')
              invoke('haystack:deploy')
              io.string.should include('Notifying Haystack of deploy with: revision: 503ce0923ed177a3ce000005, user: batman')
              io.string.should include('ppsignal has been notified of this deploy!')
            end

            context "with overridden revision" do
              before do
                @capistrano_config.set(:haystack_revision, 'abc123')
              end
              it "should add the correct marker data" do
                Haystack::Marker.should_receive(:new).with(
                  {
                    :revision => 'abc123',
                    :user => 'batman'
                  },
                  kind_of(Haystack::Config),
                  kind_of(Logger)
                ).and_return(@marker)

                invoke('haystack:deploy')
              end
            end
          end

          it "should not transmit data" do
            invoke('haystack:deploy')
            io.string.should include('Notifying Haystack of deploy with: revision: 503ce0923ed177a3ce000005, user: batman')
            io.string.should include('Something went wrong while trying to notify Haystack:')
          end
        end

        context "when not active for this environment" do
          before do
            @capistrano_config.set(:rails_env, 'nonsense')
          end

          it "should not send deploy marker" do
            Haystack::Marker.should_not_receive(:new)
            invoke('haystack:deploy')
            io.string.should include("Not loading: config for 'nonsense' not found")
          end
        end
      end
    end
  end
end
