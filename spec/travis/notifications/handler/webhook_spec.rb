require 'spec_helper'
require 'support/active_record'
require 'support/formats'

describe Travis::Notifications::Handler::Webhook do
  include Support::ActiveRecord
  include Support::Formats

  let(:http)  { Faraday::Adapter::Test::Stubs.new }
  let(:build) { Factory(:build, :config => { 'notifications' => { 'webhooks' => 'http://example.com/' } }) }
  let(:io)    { StringIO.new }

  before do
    Travis.logger = Logger.new(io)
    Travis.config.notifications = [:webhook]

    Travis::Notifications::Handler::Webhook.http_client = Faraday.new do |f|
      f.request :url_encoded
      f.adapter :test, http
    end
  end

  it 'sends webhook notifications to a url given as a string' do
    target = 'http://evome.fr/notifications'
    build.config[:notifications][:webhooks] = target
    verify_finished_build(build, target)
  end

  it 'sends webhook notifications to the urls given as an array' do
    targets = ['http://evome.fr/notifications', 'http://example.com/']
    build.config[:notifications][:webhooks] = targets
    verify_finished_build(build, *targets)
  end

  it 'sends no webhook if the given url is blank' do
    build.config[:notifications][:webhooks] = ''
    # No need to assert anything here as Faraday would complain about a request not being stubbed <3
    verify_finished_build(build)
  end

  it 'sends webhook notifications to a url given at a "urls" key' do
    target = 'http://evome.fr/notifications'
    build.config[:notifications][:webhooks] = {:urls => target}
    verify_finished_build(build, target)
  end

  it 'sends webhook notifications to the urls given at a "urls" key' do
    targets = ['http://evome.fr/notifications', 'http://example.com/']
    build.config[:notifications][:webhooks] = {:urls => targets}
    verify_finished_build(build, *targets)
  end

  it 'sends webhook notifications on start to a url given at a "urls" key' do
    target = 'http://evome.fr/notifications'
    build.config[:notifications][:webhooks] = {:on_start => true, :urls => target}
    verify_started_build(build, target)
    verify_finished_build(build, target)
  end

  it 'sends webhook notifications on start to the urls given as an array' do
    targets = ['http://evome.fr/notifications', 'http://example.com/']
    build.config[:notifications][:webhooks] = {:on_start => true, :urls => targets}
    verify_started_build(build, *targets)
    verify_finished_build(build, *targets)
  end

  it 'sends no webhook on start by default' do
    build.config[:notifications][:webhooks] = {:on_start => true}
    verify_started_build(build)
  end

  describe 'logging' do
    it 'logs a successful request' do
      http.post('/') {[ 200, {}, 'nono.' ]}
      dispatch('build:finished', build)
      io.string.should include('[webhook] Successfully notified http://example.com/')
    end

    it 'warns about a failed request' do
      http.post('/') {[ 403, {}, 'nono.' ]}
      dispatch('build:finished', build)
      io.string.should include('[webhook] Could not notify http://example.com/. Status: 403 ("nono.")')
    end
  end

  def verify_started_build(build, *urls)
    verify_targets(build, 'build:started', build.repository, *urls)
  end

  def verify_finished_build(build, *urls)
    verify_targets(build, 'build:finished', build, *urls)
  end

  def verify_targets(build, event, payload_object, *urls)
    urls.each do |url|
      uri = URI.parse(url)
      http.post uri.path do |env|
        env[:url].host.should == uri.host
        env[:url].path.should == uri.path
        env[:request_headers]['Authorization'].should == authorization_for(build)

        payload = normalize_json(Travis::Notifications::Handler::Webhook::Payload.new(payload_object).to_hash)

        payload_from(env).keys.sort.should == payload.keys.map(&:to_s).sort
      end
    end

    dispatch(event, build)

    http.verify_stubbed_calls
  end

  def dispatch(event, build)
    Travis::Notifications.dispatch(event, build)
  end

  def payload_from(env)
    JSON.parse(Rack::Utils.parse_query(env[:body])['payload'])
  end

  def authorization_for(object)
    Travis::Notifications::Handler::Webhook.new.send(:authorization, object)
  end
end

