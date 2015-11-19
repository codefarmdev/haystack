require 'spec_helper'

describe Haystack::Transaction::Formatter do
  before :all do
    start_agent
  end

  let(:klass) { Haystack::Transaction::Formatter }
  let(:formatter) { klass.new(transaction) }
  subject { formatter }
  before { transaction.stub(:fullpath => '/foo') }

  describe "#to_hash" do
    subject { formatter.to_hash }

    context "with a regular request" do
      let(:transaction) { regular_transaction }
      before { transaction.truncate! }

      its(:keys) { should =~ [:request_id, :log_entry, :failed] }
      its([:request_id]) { should == '1' }
      its([:log_entry]) { should == {
          :action => "BlogPostsController#show",
          :duration => be_within(0.01).of(100.0),
          :end => 1389783600.1,
          :environment => {},
          :kind => "http_request",
          :path => "/foo",
          :session_data => {},
          :revision => nil,
          :params => {},
          :time => 1389783600.0,
      } }
      its([:events]) { should be_nil }
      its([:failed]) { should be_false }
    end

    context "with a regular request when queue time is present" do
      let(:transaction) { regular_transaction_with_x_request_start }
      before { transaction.truncate! }

      context "log_entry content" do
        subject { formatter.to_hash[:log_entry] }

        its([:queue_duration]) { should be_within(0.01).of(40.0) }
      end
    end

    context "when the APP_REVISION environment variable is present" do
      let(:transaction) { regular_transaction }
      before do
        Haystack.agent.stub(:revision => 'foo')
      end

      it "should store the APP_REVISION" do
        subject.to_hash[:log_entry][:revision].should == 'foo'
      end
    end

    context "with a background request without payload" do
      let(:transaction) do
        Haystack::Transaction.new(
          '123',
          {},
          {
            :kind   => 'web',
            :action => 'foo#bar',
            :params => {'foo' => 'bar'}
          }
        )
      end

      before { transaction.send(:add_sanitized_context!) }

      it "should get the kind and action from the transaction" do
        subject.to_hash.should == {
          :request_id => '123',
          :log_entry  => {
            :path         => '/foo',
            :kind         => 'web',
            :action       => 'foo#bar',
            :time         => nil,
            :environment  => {},
            :session_data => {},
            :revision     => nil,
            :params       => {'foo' => 'bar'}
          },
          :failed => false
        }
      end
    end

    context "with an exception request" do
      let(:transaction) { transaction_with_exception }

      its(:keys) { should =~ [:request_id, :log_entry, :failed, :exception] }
      its([:request_id]) { should == '1' }
      its([:failed]) { should be_true }

      context "log_entry content" do
        subject { formatter.to_hash[:log_entry] }

        its([:tags]) { should == {'user_id' => 123} }
        its([:action]) { should == 'BlogPostsController#show' }
        its([:params]) { should == {'action' => 'show', 'controller' => 'blog_posts', 'id' => '1'} }

        context "when send_params in the config is false" do
          before { Haystack.config.config_hash[:send_params] = false }
          after { Haystack.config.config_hash[:send_params] = true }

          it "should not send the params" do
            subject[:params].should be_nil
          end
        end
      end

      context "exception content" do
        subject { formatter.to_hash[:exception] }

        it "should set the exception" do
          subject.should eql(transaction_with_exception.exception)
        end
        its(:keys) { should =~ [:exception, :message, :backtrace] }
        its([:exception]) { should == 'ArgumentError' }
        its([:message]) { should == 'oh no' }
      end
    end

    context "with a slow request" do
      let(:transaction) { slow_transaction }

      its(:keys) { should =~ [:request_id, :log_entry, :failed, :events] }
      its([:request_id]) { should == '1' }
      its([:log_entry]) { should == {
          :action => "BlogPostsController#show",
          :duration => be_within(0.01).of(200.0),
          :end => 1389783600.200002,
          :environment => {},
          :params => {
            'action' => 'show',
            'controller' => 'blog_posts',
            'id' => '1'
          },
          :kind => "http_request",
          :path => "/blog",
          :session_data => {},
          :revision => nil,
          :time => 1389783600.0,
          :db_runtime => 500,
          :view_runtime => 500,
          :request_format => 'html',
          :request_method => 'GET',
          :status => '200'
      } }
      its([:failed]) { should be_false }

      context "when send_params in the config is false" do
        before { Haystack.config.config_hash[:send_params] = false }
        after { Haystack.config.config_hash[:send_params] = true }

        it "should not send the params" do
          subject[:log_entry][:params].should be_nil
        end
      end

      context "events content" do
        subject { formatter.to_hash[:events] }

        its(:length) { should == 1 }
        its(:first) { should == {
          :name => "query.mongoid",
          :duration => be_within(0.01).of(100.0),
          :time => 1389783600.0,
          :end => 1389783600.1,
          :payload => {
            :path => "/blog",
            :action => "show",
            :controller => "BlogPostsController",
            :params => {
              'action' => 'show',
              'controller' => 'blog_posts',
              'id' => '1'
            },
            :request_format => "html",
            :request_method => "GET",
            :status => "200",
            :view_runtime => 500,
            :db_runtime => 500
          }
        } }
      end
    end

    context "with a background request" do
      let(:payload) { create_background_payload }
      let(:transaction) { background_job_transaction({}, payload) }

      its(:keys) { should =~ [:request_id, :log_entry, :failed] }
      its([:request_id]) { should == '1' }
      its([:log_entry]) { should == {
        :action => "BackgroundJob#perform",
        :duration => be_within(0.01).of(100.0),
        :end => 1389783600.1,
        :queue_duration => 10000.0,
        :priority => 1,
        :attempts => 0,
        :queue => 'default',
        :environment => {},
        :kind => "background_job",
        :path => "/foo",
        :session_data => {},
        :params => {},
        :revision => nil,
        :time => 1389783600.0,
      } }
      its([:failed]) { should be_false }

      context "when queue_time is zero" do
        let(:payload) { create_background_payload(:queue_start => 0) }

        context "log entry" do
          subject { formatter.to_hash[:log_entry] }

          its([:queue_duration]) { should be_nil }
        end
      end
    end
  end

  describe "#clean_backtrace" do
    let(:transaction) { regular_transaction }

    context "when backtrace is nil" do
      let(:error) { double(:backtrace => nil) }

      it "should not raise an error when backtrace is `nil`" do
        expect {
          formatter.send(:clean_backtrace, error)
        }.to_not raise_error
      end

      it "should always return an array" do
        expect( formatter.send(:clean_backtrace, error) ).to be_a(Array)
      end
    end
  end
end
