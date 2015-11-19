require 'spec_helper'

if capistrano2_present?
  require 'capistrano'
  require 'capistrano/configuration'
  require 'haystack/capistrano'

  describe "Capistrano 2 integration" do
    let(:config) { project_fixture_config }

    before :all do
      @capistrano_config = Capistrano::Configuration.new
      Haystack::Integrations::Capistrano.tasks(@capistrano_config)
    end

    it "should have a deploy task" do
      @capistrano_config.find_task('haystack:deploy').should_not be_nil
    end

    describe "haystack:deploy task" do
      before do
        @capistrano_config.set(:rails_env, 'production')
        @capistrano_config.set(:repository, 'master')
        @capistrano_config.set(:deploy_to, '/home/username/app')
        @capistrano_config.set(:current_release, '')
        @capistrano_config.set(:current_revision, '503ce0923ed177a3ce000005')
        @capistrano_config.dry_run = false
        ENV['USER'] = 'batman'
        ENV['PWD'] = project_fixture_path
      end

      context "config" do
        before do
          @capistrano_config.dry_run = true
        end

        it "should be instantiated with the right params" do
          Haystack::Config.should_receive(:new).with(
            project_fixture_path,
            'production',
            {},
            kind_of(Capistrano::Logger)
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
              kind_of(Capistrano::Logger)
            )
          end

          context "when rack_env is used instead of rails_env" do
            before do
              @capistrano_config.unset(:rails_env)
              @capistrano_config.set(:rack_env, 'rack_production')
            end

            it "should be instantiated with the right params" do
              Haystack::Config.should_receive(:new).with(
                project_fixture_path,
                'rack_production',
                {:name => 'AppName'},
                kind_of(Capistrano::Logger)
              )
            end
          end
        end

        after { @capistrano_config.find_and_execute_task('haystack:deploy') }
      end

      context "send marker" do
        before :all do
          @io = StringIO.new
          @logger = Capistrano::Logger.new(:output => @io)
          @logger.level = Capistrano::Logger::MAX_LEVEL
          @capistrano_config.logger = @logger
        end

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
              @logger
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
                kind_of(Capistrano::Logger)
              ).and_return(@marker)

              @capistrano_config.find_and_execute_task('haystack:deploy')
            end

            it "should transmit data" do
              @transmitter.should_receive(:transmit).and_return('200')
              @capistrano_config.find_and_execute_task('haystack:deploy')
              @io.string.should include('Notifying Haystack of deploy with: revision: 503ce0923ed177a3ce000005, user: batman')
              @io.string.should include('Haystack has been notified of this deploy!')
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
                  kind_of(Capistrano::Logger)
                ).and_return(@marker)

                @capistrano_config.find_and_execute_task('haystack:deploy')
              end
            end
          end

          it "should not transmit data" do
            @capistrano_config.find_and_execute_task('haystack:deploy')
            @io.string.should include('Notifying Haystack of deploy with: revision: 503ce0923ed177a3ce000005, user: batman')
            @io.string.should include('Something went wrong while trying to notify Haystack:')
          end

          context "dry run" do
            before { @capistrano_config.dry_run = true }

            it "should not send deploy marker" do
              @marker.should_not_receive(:transmit)
              @capistrano_config.find_and_execute_task('haystack:deploy')
              @io.string.should include('Dry run: Deploy marker not actually sent.')
            end
          end
        end

        context "when not active for this environment" do
          before do
            @capistrano_config.set(:rails_env, 'nonsense')
          end

          it "should not send deploy marker" do
            Haystack::Marker.should_not_receive(:new)
            @capistrano_config.find_and_execute_task('haystack:deploy')
            @io.string.should include("Not loading: config for 'nonsense' not found")
          end
        end
      end
    end
  end
end
