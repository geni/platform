require 'test_helper'

module Platform
  class ApplicationLogTest < Platform::TestCase

    test 'a log line belongs to its application and user' do
      log = Platform::ApplicationLog.create!(application: app, user: user, event: 'profile.get')

      assert_equal app.id,  log.reload.application.id
      assert_equal user.id, log.user.id
    end

    ##########################################################################
    #### The required user
    ####
    #### user_id is nullable in the schema and the only writer of this table --
    #### Platform::Api::BaseController#log_api_call -- passes
    ####
    ####   user_id: Platform::Config.current_user.try(:id)
    ####
    #### which is nil for an anonymous call (the API allows public calls, and the
    #### client_credentials grant has no user at all).  `belongs_to :user` was required, because
    #### Rails 5 made belongs_to required by default, so those rows failed validation -- and the
    #### writer uses #create rather than #create!, so the failure was silent: every API call
    #### without a logged-in user was dropped from the log and nothing reported it.
    ####
    #### Same defect, and same fix, as on Platform::Oauth::OauthToken#user.
    ##########################################################################

    test 'a log line can be recorded without a user' do
      log = Platform::ApplicationLog.create!(application: app, event: 'client_credentials')

      assert_nil log.reload.user
      assert_nil log.user_id
    end

    test 'a log line with no user persists, which is what log_api_call relies on' do
      # #create, not #create!: log_api_call must not raise on an anonymous call, and must not
      # quietly drop the row either.
      log = Platform::ApplicationLog.create(application: app, event: 'client_credentials')

      assert_equal true, log.persisted?
      assert_equal 1, Platform::ApplicationLog.where(application_id: app.id).count
    end

    # The application is still required: a log line that names no application cannot be
    # attributed to anything and is what the metric rollups read.
    test 'a log line still requires an application' do
      ex = assert_raise ActiveRecord::RecordInvalid do
        Platform::ApplicationLog.create!(user: user, event: 'profile.get')
      end
      assert_match(/application/i, ex.message)
    end

    test 'the request fields round-trip' do
      log = Platform::ApplicationLog.create!(
        application: app,
        user: user,
        event: 'profile.get',
        controller: 'api/profiles',
        action: 'show',
        request_method: 'GET',
        host: 'www.example.com',
        ip: '203.0.113.9',
        country: 'US',
        user_agent: 'curl/8.0',
        duration: 42,
      ).reload

      assert_equal 'profile.get',  log.event
      assert_equal 'api/profiles', log.controller
      assert_equal 'show',         log.action
      assert_equal 'GET',          log.request_method
      assert_equal 'www.example.com', log.host
      assert_equal '203.0.113.9',  log.ip
      assert_equal 'US',           log.country
      assert_equal 'curl/8.0',     log.user_agent
      assert_equal 42,             log.duration
    end

    ##########################################################################
    #### The serialized data column
    ####
    #### Platform::ApplicationMetric reads this table with raw SQL, so the column has to stay
    #### readable as text as well as through the coder.
    ##########################################################################

    test 'data round-trips through the YAML coder' do
      log = Platform::ApplicationLog.create!(application: app, user: user,
                                             data: { 'params' => { 'id' => 7 } })

      assert_equal({ 'params' => { 'id' => 7 } }, log.reload.data)
    end

    test 'data is nil when nothing was stored' do
      assert_nil Platform::ApplicationLog.create!(application: app, user: user).reload.data
    end

    test 'logs are destroyed with their application' do
      Platform::ApplicationLog.create!(application: app, user: user, event: 'profile.get')
      application_id = app.id

      app.destroy

      assert_equal 0, Platform::ApplicationLog.where(application_id: application_id).count
    end

  end # class ApplicationLogTest
end # module Platform
