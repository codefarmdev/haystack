require 'spec_helper'

describe Haystack::JSExceptionTransaction do
  let(:transaction) { Haystack::JSExceptionTransaction.new(data) }
  let(:data) do
    {
      'name'        => 'TypeError',
      'message'     => 'foo is not a valid method',
      'action'      => 'ExceptionIncidentComponent',
      'path'        => 'foo.bar/moo',
      'environment' => {"user_agent" => "Mozilla/5.0"},
      'tags'        => {"intercom_user_id" => "abc123"},
      'backtrace'   => [
        'foo.bar/js:11:1',
        'foo.bar/js:22:2',
      ]
    }
  end

  describe "#type" do
    it "should return `:exception`" do
      expect( transaction.type ).to eql :exception
    end
  end

  describe "#action" do
    it "should return the action" do
      expect( transaction.action ).to eql 'ExceptionIncidentComponent'
    end
  end

  describe "#clear_events" do
    it "should respond to `clear_events!`" do
      expect( transaction ).to respond_to :clear_events!
    end
  end

  describe "#convert_values_to_primitives!" do
    it "should respond to `convert_values_to_primitives!`" do
      expect( transaction ).to respond_to :convert_values_to_primitives!
    end
  end

  describe "#events" do
    it "should respond to `events` with an empty array" do
      expect( transaction.events ).to eql []
    end
  end

  describe "#to_hash" do
    around do |sample|
      Timecop.freeze(Time.at(123)) { sample.run }
    end

    before do
      SecureRandom.stub(:uuid => 'uuid')
      Haystack.stub(:agent => double(:revision => 'abcdef'))
    end

    it "should generate a hash based on the given data" do
      expect( transaction.to_hash).to eql({
        :request_id => 'uuid',
        :log_entry => {
          :action      => 'ExceptionIncidentComponent',
          :path        => 'foo.bar/moo',
          :kind        => 'frontend',
          :time        => 123,
          :environment => {"user_agent" => "Mozilla/5.0"},
          :tags        => {"intercom_user_id" => "abc123"},
          :revision    => 'abcdef'
        },
        :exception => {
          :exception => 'TypeError',
          :message   => 'foo is not a valid method',
          :backtrace => [
            'foo.bar/js:11:1',
            'foo.bar/js:22:2',
          ]
        },
        :failed => true
      })
    end

    describe "#complete!" do
      it "should enqueue itself" do
        expect( Haystack ).to receive(:enqueue).with(transaction)

        transaction.complete!
      end
    end

  end
end
