require 'spec_helper'

describe Haystack::Transmitter do
  let(:config) { project_fixture_config }
  let(:action) { 'action' }
  let(:instance) { Haystack::Transmitter.new(action, config) }
  let!(:payload)  { Haystack::ZippedPayload.new({'the' => 'payload'}) }

  describe "#uri" do
    before { Socket.stub(:gethostname => 'app1.local') }

    subject { instance.uri.to_s }

    it { should include 'https://push.haystack.com/1/action?' }
    it { should include 'api_key=abc' }
    it { should include 'hostname=app1.local' }
    it { should include 'name=TestApp' }
    it { should include 'environment=production' }
    it { should include "gem_version=#{Haystack::VERSION}" }
  end

  describe "#transmit" do
    before do
      stub_request(
        :post,
        "https://push.haystack.com/1/action?api_key=abc&environment=production&gem_version=#{Haystack::VERSION}&hostname=#{Socket.gethostname}&name=TestApp"
      ).with(
        :body => Zlib::Deflate.deflate("{\"the\":\"payload\"}", Zlib::BEST_SPEED),
        :headers => {
          'Content-Encoding' => 'gzip',
          'Content-Type' => 'application/json; charset=UTF-8',
        }
      ).to_return(
        :status => 200
      )
    end

    it "should post the ZippedPayload" do
      instance.transmit(payload).should == '200'
    end

    it "should not instantiate a new ZippedPayload" do
      expect( Haystack::ZippedPayload ).to_not receive(:new)
      instance.transmit(payload)
    end

    context "when not given a ZippedPayload, but a hash" do
      it "should post the ZippedPayload" do
        instance.transmit({'the' => 'payload'}).should == '200'
      end

      it "should instantiate a new ZippedPayload" do
        expect( Haystack::ZippedPayload ).to receive(:new).with({'the' => 'payload'})
                                                           .and_return(payload)
                                                           .at_least(:once)
        instance.transmit({'the' => 'payload'})
      end
    end
  end

  describe "#http_post" do
    before do
      Socket.stub(:gethostname => 'app1.local')
    end

    subject { instance.send(:http_post, payload) }

    its(:body) { should == Zlib::Deflate.deflate("{\"the\":\"payload\"}", Zlib::BEST_SPEED) }
    its(:path) { should == instance.uri.request_uri }

    it "should have the correct headers" do
      subject['Content-Type'].should == 'application/json; charset=UTF-8'
      subject['Content-Encoding'].should == 'gzip'
    end
  end

  describe ".CA_FILE_PATH" do
    subject { Haystack::Transmitter::CA_FILE_PATH }

    it { should include('resources/cacert.pem') }
    it("should exist") { File.exists?(subject).should be_true }
  end

  describe "#http_client" do
    subject { instance.send(:http_client) }

    context "with a http uri" do
      let(:config) { project_fixture_config('test') }

      it { should be_instance_of(Net::HTTP) }
      its(:proxy?) { should be_false }
      its(:use_ssl?) { should be_false }
    end

    context "with a https uri" do
      let(:config) { project_fixture_config('production') }

      it { should be_instance_of(Net::HTTP) }
      its(:proxy?) { should be_false }
      its(:use_ssl?) { should be_true }
      its(:verify_mode) { should == OpenSSL::SSL::VERIFY_PEER }
      its(:ca_file) { Haystack::Transmitter::CA_FILE_PATH }
    end

    context "with a proxy" do
      let(:config) { project_fixture_config('production', :http_proxy => 'http://localhost:8080') }

      its(:proxy?) { should be_true }
      its(:proxy_address) { should == 'localhost' }
      its(:proxy_port) { should == 8080 }
    end
  end
end
