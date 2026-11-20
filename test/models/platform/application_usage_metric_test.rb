require 'test_helper'

module Platform
  class ApplicationUsageMetricTest < Platform::TestCase

    INTERVAL = Time.utc(2026, 1, 1, 12, 0, 0)

    test 'interval_duration is fifteen minutes' do
      assert_equal 15.minutes, Platform::ApplicationUsageMetric.interval_duration
    end

    ##########################################################################
    #### find_or_create
    ####
    #### Keyed on three things rather than two: this table holds one row per event name, which is
    #### what makes it a usage breakdown rather than a single count.
    ##########################################################################

    test 'find_or_create creates one row per application, interval and event' do
      first  = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL, 'profile.get')
      second = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL, 'profile.get')

      assert_equal first.id, second.id
      assert_equal 1, Platform::ApplicationUsageMetric.where(application_id: app.id).count
    end

    test 'find_or_create keys on the event' do
      get = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL, 'profile.get')
      put = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL, 'profile.update')

      assert_not_equal get.id, put.id
      assert_equal 'profile.get',    get.event
      assert_equal 'profile.update', put.event
    end

    test 'find_or_create keys on the interval and the application' do
      base  = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL, 'profile.get')
      later = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL + 15.minutes, 'profile.get')
      other = Platform::ApplicationUsageMetric.find_or_create(create_app(name: 'Other'), INTERVAL, 'profile.get')

      assert_equal 3, [base.id, later.id, other.id].uniq.size
    end

    ##########################################################################
    #### calculate_metric
    ##########################################################################

    test 'calculate_metric writes one row per event, with its count' do
      log('profile.get',    INTERVAL + 1.minute,  100)
      log('profile.get',    INTERVAL + 2.minutes, 300)
      log('profile.update', INTERVAL + 3.minutes, 50)

      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 2, Platform::ApplicationUsageMetric.where(application_id: app.id, interval: INTERVAL).count
      assert_equal 2, metric('profile.get').count
      assert_equal 1, metric('profile.update').count
    end

    test 'calculate_metric averages the duration' do
      log('profile.get', INTERVAL + 1.minute,  100)
      log('profile.get', INTERVAL + 2.minutes, 300)

      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 200, metric('profile.get').avg_response_time
    end

    # error_count is written unconditionally -- the model's own comment says counting errors is
    # still to be added -- so it is zero rather than nil, which is worth pinning: a reader cannot
    # tell "no errors" from "not measured" by looking at the column.
    test 'calculate_metric zeroes the error count' do
      log('profile.get', INTERVAL + 1.minute, 100)

      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, metric('profile.get').error_count
    end

    test 'calculate_metric excludes logs outside the window' do
      log('profile.get', INTERVAL,                 100) # inclusive start
      log('profile.get', INTERVAL - 1.minute,      100)
      log('profile.get', INTERVAL + 15.minutes,    100) # exclusive end

      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 1, metric('profile.get').count
    end

    test 'calculate_metric is scoped to its application' do
      log('profile.get', INTERVAL + 1.minute, 100, create_app(name: 'Other'))

      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, Platform::ApplicationUsageMetric.where(application_id: app.id).count
    end

    test 'calculate_metric writes nothing when there are no logs' do
      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, Platform::ApplicationUsageMetric.where(application_id: app.id).count
    end

    test 'calculate_metric overwrites its own rows rather than adding to them' do
      log('profile.get', INTERVAL + 1.minute, 100)
      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)
      Platform::ApplicationUsageMetric.calculate_metric(app, INTERVAL)

      assert_equal 1, Platform::ApplicationUsageMetric.where(application_id: app.id).count
      assert_equal 1, metric('profile.get').count
    end

private

    def metric(event)
      Platform::ApplicationUsageMetric.where(application_id: app.id, interval: INTERVAL,
                                             event: event).first
    end

    def log(event, created_at, duration, application = app)
      Platform::ApplicationLog.create!(application: application, user: user, event: event,
                                       duration: duration, created_at: created_at)
    end

  end # class ApplicationUsageMetricTest
end # module Platform
