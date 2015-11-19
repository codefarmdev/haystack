require 'spec_helper'
require 'fileutils'

unless running_jruby?
  describe Haystack::IPC do
    before :all do
      start_agent
    end
    after :all do
      Haystack::IPC::Client.stop
      Haystack::IPC::Server.stop
    end

    subject { Haystack::IPC }

    describe ".forked!" do
      it "should stop the server, start the client and stop the haystack thread" do
        Haystack::IPC::Server.should_receive(:stop)
        Haystack::IPC::Client.should_receive(:start)
        Haystack.agent.should_receive(:stop_thread)

        subject.forked!
      end
    end

    describe Haystack::IPC::Server do
      subject { Haystack::IPC::Server }

      describe ".start" do
        before do
          FileUtils.rm_rf(File.join(project_fixture_path, 'tmp'))
          Process.stub(:pid => 100)
        end

        it "should start a DRb server" do
          DRb.should_receive(:start_service).with(
            instance_of(String),
            Haystack::IPC::Server
          )
          subject.start
          subject.uri.should == 'drbunix:/tmp/haystack-100'
        end

        context "when a tmp path exists in the project path" do
          before do
            FileUtils.mkdir_p(File.join(project_fixture_path, 'tmp'))
          end

          it "should use a uri in the project path" do
            subject.start
            subject.uri.should == "drbunix:#{project_fixture_path}/tmp/haystack-100"
          end
        end
      end

      describe ".stop" do
        it "should stop the DRb server" do
          DRb.should_receive(:stop_service)
          subject.stop
        end
      end

      describe ".enqueue" do
        let(:transaction) { regular_transaction }

        it "should enqueue" do
          Haystack.agent.aggregator.has_transactions?.should be_false
          subject.enqueue(transaction)
          Haystack.agent.aggregator.has_transactions?.should be_true
        end
      end
    end

    describe Haystack::IPC::Client do
      before do
        Haystack::IPC::Client.stop
      end

      subject { Haystack::IPC::Client }

      describe ".start" do
        it "should start the client" do
          subject.active?.should be_false

          subject.start

          subject.server.should be_instance_of(DRbObject)
          subject.active?.should be_true
        end
      end

      describe ".stop" do
        it "should stop the client" do
          subject.start
          subject.stop

          subject.server.should be_nil
          subject.active?.should be_false
        end
      end

      describe ".enqueue" do
        let(:transaction) { regular_transaction }

        it "should send the transaction to the server" do
          subject.start
          subject.server.should_receive(:enqueue).with(transaction)
          subject.enqueue(transaction)
        end
      end
    end

    describe "integration between client and server" do
      it "should enqueue a transaction on the master" do
        Haystack::IPC::Server.start

        fork do
          Haystack::IPC.forked!
          Haystack::IPC::Client.enqueue(regular_transaction)
        end

        Haystack.agent.should_receive(:enqueue).with(instance_of(Haystack::Transaction))

        sleep 1 # Wait for the forked process to do it's work
      end
    end
  end
end
