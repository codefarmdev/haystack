require 'spec_helper'
require './spec/support/mocks/mock_extension'

describe Haystack do
  before do
    # Make sure we have a clean state because we want to test
    # initialization here.
    Haystack.agent.shutdown if Haystack.agent
    Haystack.config = nil
    Haystack.agent = nil
    Haystack.extensions.clear
  end

  let(:transaction) { regular_transaction }

  describe ".config=" do
    it "should set the config" do
      config = project_fixture_config
      Haystack.logger.should_not_receive(:level=)

      Haystack.config = config
      Haystack.config.should == config
    end
  end

  describe ".extensions" do
    it "should keep a list of extensions" do
      Haystack.extensions.should be_empty
      Haystack.extensions << Haystack::MockExtension
      Haystack.extensions.should have(1).item
    end
  end

  describe ".start" do
    it "should do nothing when config is not loaded" do
      Haystack.logger.should_receive(:error).with(
        "Can't start, no config loaded"
      )
      Haystack.start
      Haystack.agent.should be_nil
    end

    context "when config is loaded" do
      before { Haystack.config = project_fixture_config }

      it "should start an agent" do
        Haystack.start
        Haystack.agent.should be_a Haystack::Agent
        Haystack.logger.level.should == Logger::INFO
      end

      it "should load integrations" do
        Haystack.should_receive(:load_integrations)
        Haystack.start
      end

      it "should load instrumentations" do
        Haystack.should_receive(:load_instrumentations)
        Haystack.start
      end

      context "when not active for this environment" do
        before { Haystack.config = project_fixture_config('staging') }

        it "should do nothing" do
          Haystack.logger.should_receive(:info).with(
            'Not starting, not active for staging'
          )
          Haystack.start
          Haystack.agent.should be_nil
        end
      end

      context "with an extension" do
        before { Haystack.extensions << Haystack::MockExtension }

        it "should call the extension's initializer" do
          Haystack::MockExtension.should_receive(:initializer)
          Haystack.start
        end
      end
    end

    describe ".load_integrations" do
      it "should require the integrations" do
        Haystack.should_receive(:require).at_least(:once)
      end

      after { Haystack.load_integrations }
    end

    describe ".load_instrumentations" do
      before { Haystack.config = project_fixture_config }

      context "Net::HTTP" do
        context "if on in the config" do
          it "should require net_http" do
            Haystack.should_receive(:require).with('haystack/instrumentations/net_http')
          end
        end

        context "if off in the config" do
          before { Haystack.config.config_hash[:instrument_net_http] = false }

          it "should not require net_http" do
            Haystack.should_not_receive(:require).with('haystack/instrumentations/net_http')
          end
        end
      end

      after { Haystack.load_instrumentations }
    end

    context "with debug logging" do
      before { Haystack.config = project_fixture_config('test') }

      it "should change the log level" do
        Haystack.start
        Haystack.logger.level.should == Logger::DEBUG
      end
    end
  end

  describe '.active?' do
    subject { Haystack.active? }

    context "without config and agent" do
      before do
        Haystack.config = nil
        Haystack.agent = nil
      end

      it { should be_false }
    end

    context "with agent and inactive config" do
      before do
        Haystack.config = project_fixture_config('nonsense')
        Haystack.agent = Haystack::Agent.new
      end

      it { should be_false }
    end

    context "with active agent and config" do
      before do
        Haystack.config = project_fixture_config
        Haystack.agent = Haystack::Agent.new
      end

      it { should be_true }
    end
  end

  context "not active" do
    describe ".enqueue" do
      it "should do nothing" do
        lambda {
          Haystack.enqueue(Haystack::Transaction.create(SecureRandom.uuid, ENV))
        }.should_not raise_error
      end
    end

    describe ".monitor_transaction" do
      it "should do nothing but still yield the block" do
        Haystack::Transaction.should_not_receive(:create)
        ActiveSupport::Notifications.should_not_receive(:instrument)
        object = double
        object.should_receive(:some_method)

        lambda {
          Haystack.monitor_transaction('perform_job.nothing') do
            object.some_method
          end
        }.should_not raise_error
      end
    end

    describe ".listen_for_exception" do
      it "should do nothing" do
        error = RuntimeError.new('specific error')
        lambda {
          Haystack.listen_for_exception do
            raise error
          end
        }.should raise_error(error)
      end
    end

    describe ".send_exception" do
      it "should do nothing" do
        lambda {
          Haystack.send_exception(RuntimeError.new)
        }.should_not raise_error
      end
    end

    describe ".add_exception" do
      it "should do nothing" do
        lambda {
          Haystack.add_exception(RuntimeError.new)
        }.should_not raise_error
      end
    end

    describe ".tag_request" do
      it "should do nothing" do
        lambda {
          Haystack.tag_request(:tag => 'tag')
        }.should_not raise_error
      end
    end
  end

  context "with config and started" do
    before do
      Haystack.config = project_fixture_config
      Haystack.start
    end

    describe ".enqueue" do
      subject { Haystack.enqueue(transaction) }

      it "forwards the call to the agent" do
        Haystack.agent.should respond_to(:enqueue)
        Haystack.agent.should_receive(:enqueue).with(transaction)
        subject
      end
    end

    describe ".monitor_transaction" do
      context "with a normall call" do
        it "should instrument and complete" do
          Haystack::Transaction.stub(:current => transaction)
          ActiveSupport::Notifications.should_receive(:instrument).with(
            'perform_job.something',
            :class => 'Something'
          ).and_yield
          transaction.should_receive(:complete!)
          object = double
          object.should_receive(:some_method)

          Haystack.monitor_transaction(
            'perform_job.something',
            :class => 'Something'
          ) do
            object.some_method
          end
        end
      end

      context "with an erroring call" do
        let(:error) { VerySpecificError.new('the roof') }

        it "should add the error to the current transaction and complete" do
          Haystack.should_receive(:add_exception).with(error)
          Haystack::Transaction.should_receive(:complete_current!)

          lambda {
            Haystack.monitor_transaction('perform_job.something') do
              raise error
            end
          }.should raise_error(error)
        end
      end
    end

    describe ".tag_request" do
      before { Haystack::Transaction.stub(:current => transaction) }

      context "with transaction" do
        let(:transaction) { double }
        it "should call set_tags on transaction" do

          transaction.should_receive(:set_tags).with({'a' => 'b'})
        end

        after { Haystack.tag_request({'a' => 'b'}) }
      end

      context "without transaction" do
        let(:transaction) { nil }

        it "should call set_tags on transaction" do
          Haystack.tag_request.should be_false
        end
      end

      it "should also listen to tag_job" do
        Haystack.should respond_to(:tag_job)
      end
    end

    describe ".transactions" do
      subject { Haystack.transactions }

      it { should be_a Hash }
    end

    describe '.logger' do
      subject { Haystack.logger }

      it { should be_a Logger }
    end

    describe ".start_logger" do
      let(:out_stream) { StringIO.new }
      let(:log_file) { File.join(path, 'haystack.log') }
      before do
        @original_stdout = $stdout
        $stdout = out_stream
        Haystack.logger.error('Log something')
      end
      after do
        $stdout = @original_stdout
      end

      context "when the log path is writable" do
        let(:path) { File.join(project_fixture_path, 'log') }
        before { Haystack.start_logger(path) }

        it "should log to file" do
          File.exists?(log_file).should be_true
          File.open(log_file).read.should include 'Log something'
        end
      end

      context "when the log path is not writable" do
        let(:path) { '/nonsense/log' }
        before { Haystack.start_logger(path) }

        it "should log to stdout" do
          Haystack.logger.error('Log to stdout')
          out_stream.string.should include 'haystack: Log to stdout'
        end
      end

      context "when we're on Heroku" do
        let(:path) { File.join(project_fixture_path, 'log') }
        before do
          ENV['DYNO'] = 'dyno1'
          Haystack.start_logger(path)
        end
        after { ENV.delete('DYNO') }

        it "should log to stdout" do
          Haystack.logger.error('Log to stdout')
          out_stream.string.should include 'haystack: Log to stdout'
        end
      end

      context "when we're on Shelly Cloud" do
        let(:path) { File.join(project_fixture_path, 'log') }
        before do
          ENV['SHELLYCLOUD_DEPLOYMENT'] = 'true'
          Haystack.start_logger(path)
        end
        after { ENV.delete('SHELLYCLOUD_DEPLOYMENT') }

        it "should log to stdout" do
          Haystack.logger.error('Log to stdout')
          out_stream.string.should include 'haystack: Log to stdout'
        end
      end

      context "when there is no in memory log" do
        it "should not crash" do
          Haystack.in_memory_log = nil
          Haystack.start_logger(nil)
        end
      end
    end

    describe '.config' do
      subject { Haystack.config }

      it { should be_a Haystack::Config }
      it 'should return configuration' do
        subject[:endpoint].should == 'https://push.haystack.com/1'
      end
    end

    describe ".post_processing_middleware" do
      before { Haystack.instance_variable_set(:@post_processing_chain, nil) }

      it "returns the default middleware stack" do
        Haystack::Aggregator::PostProcessor.should_receive(:default_middleware)
        Haystack.post_processing_middleware
      end

      it "returns a chain when called without a block" do
        instance = Haystack.post_processing_middleware
        instance.should be_an_instance_of Haystack::Aggregator::Middleware::Chain
      end

      context "when passing a block" do
        it "yields an haystack middleware chain" do
          Haystack.post_processing_middleware do |o|
            o.should be_an_instance_of Haystack::Aggregator::Middleware::Chain
          end
        end
      end
    end

    describe ".send_exception" do
      let(:tags)      { nil }
      let(:exception) { VerySpecificError.new }
      before          { Haystack::IPC.stub(:current => false) }

      it "should send the exception to Haystack" do
        agent = double(:shutdown => true, :active? => true)
        Haystack.stub(:agent).and_return(agent)
        agent.should_receive(:send_queue)
        agent.should_receive(:enqueue).with(kind_of(Haystack::Transaction))

        Haystack::Transaction.should_receive(:create).and_call_original
      end

      context "with tags" do
        let(:tags) { {:a => 'a', :b => 'b'} }

        it "should tag the request before sending" do
          transaction = Haystack::Transaction.create(SecureRandom.uuid, {})
          Haystack::Transaction.stub(:create => transaction)
          transaction.should_receive(:set_tags).with(tags)
        end
      end

      it "should not send the exception if it's in the ignored list" do
        Haystack.stub(:is_ignored_exception? => true)
        Haystack::Transaction.should_not_receive(:create)
      end

      context "when given class is not an exception" do
        let(:exception) { double }

        it "should log a message" do
          expect( Haystack.logger ).to receive(:error).with('Can\'t send exception, given value is not an exception')
        end

        it "should not send the exception" do
          expect( Haystack::Transaction ).to_not receive(:create)
        end
      end

      after do
        Haystack.send_exception(exception, tags) rescue Exception
      end
    end

    describe ".listen_for_exception" do
      it "should call send_exception and re-raise" do
        Haystack.should_receive(:send_exception).with(kind_of(Exception))
        lambda {
          Haystack.listen_for_exception do
            raise "I am an exception"
          end
        }.should raise_error(RuntimeError, "I am an exception")
      end
    end

    describe ".add_exception" do
      before { Haystack::Transaction.stub(:current => transaction) }
      let(:exception) { RuntimeError.new('I am an exception') }

      it "should add the exception to the current transaction" do
        transaction.should_receive(:add_exception).with(exception)

        Haystack.add_exception(exception)
      end

      it "should do nothing if there is no current transaction" do
        Haystack::Transaction.stub(:current => nil)

        transaction.should_not_receive(:add_exception).with(exception)

        Haystack.add_exception(exception)
      end

      it "should not add the exception if it's in the ignored list" do
        Haystack.stub(:is_ignored_exception? => true)

        transaction.should_not_receive(:add_exception).with(exception)

        Haystack.add_exception(exception)
      end

      it "should do nothing if the exception is nil" do
        transaction.should_not_receive(:add_exception)

        Haystack.add_exception(nil)
      end
    end

    describe ".without_instrumentation" do
      let(:transaction) { double }
      before { Haystack::Transaction.stub(:current => transaction) }

      it "should pause and unpause the transaction around the block" do
        transaction.should_receive(:pause!)
        transaction.should_receive(:resume!)
      end

      context "without transaction" do
        let(:transaction) { nil }

        it "should not crash" do
          # just execute the after block
        end
      end

      after do
        Haystack.without_instrumentation do
          # nothing
        end
      end
    end

    describe ".is_ignored_exception?" do
      let(:exception) { StandardError.new }
      before do
        Haystack.stub(
          :config => {:ignore_exceptions => 'StandardError'}
        )
      end

      subject { Haystack.is_ignored_exception?(exception) }

      it "should return true if it's in the ignored list" do
        should be_true
      end

      context "when exception is not in the ingore list" do
        let(:exception) { Object.new }

        it "should return false" do
          should be_false
        end
      end
    end

    describe ".is_ignored_action?" do
      let(:action) { 'TestController#isup' }
      before do
        Haystack.stub(
          :config => {:ignore_actions => 'TestController#isup'}
        )
      end

      subject { Haystack.is_ignored_action?(action) }

      it "should return true if it's in the ignored list" do
        should be_true
      end

      context "when action is not in the ingore list" do
        let(:action) { 'TestController#other_action' }

        it "should return false" do
          should be_false
        end
      end
    end
  end
end
