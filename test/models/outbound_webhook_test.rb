# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe OutboundWebhook do
  let(:webhook_attributes) do
    {
      stage: stages(:test_staging),
      project: projects(:test),
      url: "https://testing.com/deploys"
    }
  end

  describe '#create' do
    it 'creates the webhook' do
      assert OutboundWebhook.create(webhook_attributes)
    end

    it 'refuses to create a duplicate webhook' do
      OutboundWebhook.create!(webhook_attributes)

      refute_valid OutboundWebhook.new(webhook_attributes)
    end

    it "validates that url begins with http:// or https://" do
      refute_valid OutboundWebhook.new(webhook_attributes.merge(url: "/foobar"))
    end

    it 'recreates a webhook after soft_delete' do
      webhook = OutboundWebhook.create!(webhook_attributes)

      assert_difference 'OutboundWebhook.count', -1 do
        webhook.soft_delete!
      end

      assert_difference 'OutboundWebhook.count', +1 do
        OutboundWebhook.create!(webhook_attributes)
      end
    end
  end

  describe '#soft_delete!' do
    let(:webhook) { OutboundWebhook.create!(webhook_attributes) }

    before { webhook }

    it 'deletes the webhook' do
      assert_difference 'OutboundWebhook.count', -1 do
        webhook.soft_delete!
      end
    end

    it 'soft deletes the webhook' do
      assert_difference  'OutboundWebhook.with_deleted { OutboundWebhook.count} ', 0 do
        webhook.soft_delete!
      end
    end

    # We have validation to stop us from having multiple of the same webhook active.
    # lets ensure that same validation doesn't stop us from having multiple of the same webhook soft-deleted.
    it 'can soft delete duplicate webhooks' do
      assert_difference 'OutboundWebhook.count', -1 do
        webhook.soft_delete!
      end

      webhook2 = OutboundWebhook.create!(webhook_attributes)
      assert_difference 'OutboundWebhook.count', -1 do
        webhook2.soft_delete!
      end
    end
  end

  describe "#connection" do
    before do
      @webhook = OutboundWebhook.create!(selected_webhook)
      @connection = @webhook.send(:connection)

      assert_equal selected_webhook[:url], @connection.url_prefix.to_s
    end

    describe "with no authorization" do
      let(:selected_webhook) { webhook_attributes }

      it "builds a connection with the correct params" do
        refute_includes @connection.headers, 'Authorization'
      end
    end

    describe "with authorization" do
      let(:selected_webhook) { webhook_attributes.merge(username: "adminuser", password: "abc123") }

      it "builds a connection with the correct params" do
        assert_equal @connection.headers['Authorization'], 'Basic YWRtaW51c2VyOmFiYzEyMw=='
      end
    end
  end

  describe "#deliver" do
    def stub_delivery
      Faraday.new(url: @webhook.url) do |builder|
        builder.adapter :test, Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('/deploys') { [response, {}, "AOK"] }
        end
      end
    end

    before do
      @webhook = OutboundWebhook.create!(webhook_attributes)
      OutboundWebhook.any_instance.stubs(:connection).returns(stub_delivery)
      OutboundWebhook.stubs(:deploy_as_json).returns({})
    end

    describe "with a successful request" do
      let(:response) { 200 }

      it "posts to the webhook url and logs" do
        assert @webhook.deliver(Deploy.new), "Deliver should succeed"
      end
    end

    describe "with an invalid request" do
      let(:response) { 400 }

      it "tries to post to the webhook url" do
        refute @webhook.deliver(Deploy.new), "Deliver should not succeed"
      end
    end
  end

  describe ".deploy_as_json" do
    it "renders a deploy" do
      json = OutboundWebhook.deploy_as_json(deploys(:succeeded_test))
      json.keys.must_include 'id'
      json.keys.must_include 'user'
      json.keys.must_include 'project'
      json.keys.must_include 'stage'
    end
  end
end
