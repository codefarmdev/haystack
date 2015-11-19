require 'spec_helper'

describe Haystack::Rack::JSExceptionCatcher do
  let(:app)            { double(:call => true) }
  let(:options)        { double }
  let(:active)         { true }
  let(:config_options) { {:enable_frontend_error_catching => true} }
  let(:config)         { project_fixture_config('production', config_options) }

  before do
    Haystack.stub(:config => config)
    config.stub(:active? => active)
  end

  describe "#initialize" do
    it "should log to the logger" do
      expect( Haystack.logger ).to receive(:debug)
        .with('Initializing Haystack::Rack::JSExceptionCatcher')

      Haystack::Rack::JSExceptionCatcher.new(app, options)
    end
  end

  describe "#call" do
    let(:catcher) { Haystack::Rack::JSExceptionCatcher.new(app, options) }

    context "when path is not `/haystack_error_catcher`" do
      let(:env) { {'PATH_INFO' => '/foo'} }

      it "should call the next middleware" do
        expect( app ).to receive(:call).with(env)
      end
    end

    context "when path is `/haystack_error_catcher`" do
      let(:transaction) { double(:complete! => true) }
      let(:env) do
        {
          'PATH_INFO'  => '/haystack_error_catcher',
          'rack.input' => double(:read => '{"foo": "bar"}')
        }
      end

      it "should create a JSExceptionTransaction" do
        expect( Haystack::JSExceptionTransaction ).to receive(:new)
          .with({'foo' => 'bar'})
          .and_return(transaction)

        expect( transaction ).to receive(:complete!)
      end

      context "when `frontend_error_catching_path` is different" do
        let(:config_options) do
          {
            :frontend_error_catching_path   => '/foo'
          }
        end

        it "should not create a transaction" do
          expect( Haystack::JSExceptionTransaction ).to_not receive(:new)
        end

        it "should call the next middleware" do
          expect( app ).to receive(:call).with(env)
        end
      end
    end

    after { catcher.call(env) }
  end

end
