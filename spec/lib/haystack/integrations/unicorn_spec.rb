require 'spec_helper'

describe "Unicorn integration" do
  let(:file) { File.expand_path('lib/haystack/integrations/unicorn.rb') }
  before(:all) do
    module Unicorn
      class HttpServer
        def worker_loop(worker)
        end
      end

      class Worker
        def close
        end
      end
    end
  end
  before do
    load file
    start_agent
  end

  it "adds behavior to Unicorn::HttpServer#worker_loop" do
    server = Unicorn::HttpServer.new
    worker = double

    Haystack.agent.should_receive(:forked!)
    server.should_receive(:original_worker_loop).with(worker)

    server.worker_loop(worker)
  end

  it "should add behavior to Unicorn::Worker#close" do
    worker = Unicorn::Worker.new

    Haystack.agent.should_receive(:shutdown).with(true, 'stopping Unicorn worker process')
    worker.should_receive(:original_close)

    worker.close
  end

  context "without unicorn" do
    before(:all) { Object.send(:remove_const, :Unicorn) }

    specify { expect { Unicorn }.to raise_error(NameError) }
    specify { expect { load file }.to_not raise_error }
  end
end
