require 'test_helper'

module Platform
  # Platform::ApplicationMetric and the four STI subclasses that differ from it only by the width
  # of the window they roll up over.
  class ApplicationMetricTest < Platform::TestCase

    INTERVAL = Time.utc(2026, 1, 1, 12, 0, 0)

    ##########################################################################
    #### Interval widths
    ####
    #### The whole STI hierarchy exists for these four numbers: #calculate_metric reads
    #### interval_duration to size its window, so getting one wrong silently rolls up the wrong
    #### span of logs.
    ##########################################################################

    test 'each subclass declares its own interval duration' do
      assert_equal 15.minutes, Platform::ApplicationMetric.interval_duration
      assert_equal 1.day,      Platform::DailyApplicationMetric.interval_duration
      assert_equal 1.week,     Platform::WeeklyApplicationMetric.interval_duration
      assert_equal 1.month,    Platform::MonthlyApplicationMetric.interval_duration
    end

    test 'the total metric inherits the base interval duration' do
      assert_equal 15.minutes, Platform::TotalApplicationMetric.interval_duration,
                   'it rolls up everything up to the interval, so the window width is unused'
    end

    ##########################################################################
    #### find_or_create
    ##########################################################################

    test 'find_or_create creates one row per application and interval' do
      first  = Platform::ApplicationMetric.find_or_create(app, INTERVAL)
      second = Platform::ApplicationMetric.find_or_create(app, INTERVAL)

      assert_equal first.id, second.id
      assert_equal 1, Platform::ApplicationMetric.where(application_id: app.id, interval: INTERVAL).count
    end

    test 'find_or_create keys on the interval' do
      first  = Platform::ApplicationMetric.find_or_create(app, INTERVAL)
      second = Platform::ApplicationMetric.find_or_create(app, INTERVAL + 15.minutes)

      assert_not_equal first.id, second.id
    end

    test 'find_or_create keys on the application' do
      first  = Platform::ApplicationMetric.find_or_create(app, INTERVAL)
      second = Platform::ApplicationMetric.find_or_create(create_app(name: 'Other'), INTERVAL)

      assert_not_equal first.id, second.id
    end

    # All five classes share platform_application_metrics, so the type column is the only thing
    # keeping a daily rollup from being handed back as the answer to a 15-minute one.
    test 'find_or_create stamps the STI type and does not cross types' do
      quarter_hourly = Platform::ApplicationMetric.find_or_create(app, INTERVAL)
      daily          = Platform::DailyApplicationMetric.find_or_create(app, INTERVAL)

      assert_equal 'Platform::ApplicationMetric',      quarter_hourly.type
      assert_equal 'Platform::DailyApplicationMetric', daily.type
      assert_not_equal quarter_hourly.id, daily.id

      assert_equal daily.id, Platform::DailyApplicationMetric.find_or_create(app, INTERVAL).id,
                   'the second call must find the daily row, not the quarter-hourly one'
    end

    ##########################################################################
    #### calculate_metric
    ##########################################################################

    test 'calculate_metric counts the distinct users active in the window' do
      a = create_user('active a')
      b = create_user('active b')

      log(a, INTERVAL)                 # the window is inclusive of its start
      log(a, INTERVAL + 5.minutes)     # same user twice is still one active user
      log(b, INTERVAL + 14.minutes)

      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 2, metric.active_user_count
    end

    test 'calculate_metric excludes logs outside the window' do
      inside = create_user('inside')
      log(inside, INTERVAL + 1.minute)
      log(create_user('before'), INTERVAL - 1.minute)
      log(create_user('after'),  INTERVAL + 15.minutes) # the window end is exclusive

      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 1, metric.active_user_count
    end

    test 'calculate_metric counts the users who joined in the window' do
      join(create_user('joined'), INTERVAL + 2.minutes)
      join(create_user('joined earlier'), INTERVAL - 1.day)

      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 1, metric.new_user_count
    end

    test 'calculate_metric is scoped to its application' do
      other = create_app(name: 'Other')
      log(create_user('theirs'), INTERVAL + 1.minute, other)
      join(create_user('theirs too'), INTERVAL + 1.minute, other)

      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, metric.active_user_count
      assert_equal 0, metric.new_user_count
    end

    test 'calculate_metric records zeroes when nothing happened' do
      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, metric.active_user_count
      assert_equal 0, metric.new_user_count
    end

    test 'calculate_metric is idempotent -- it overwrites its own row' do
      log(create_user('one'), INTERVAL + 1.minute)
      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)
      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 1, Platform::ApplicationMetric.where(application_id: app.id, interval: INTERVAL).count
      assert_equal 1, metric.active_user_count
    end

    # The point of the subclasses: the same logs produce different counts depending on how wide
    # the window is.  A log six hours in is outside a 15-minute window and inside a daily one.
    test 'a subclass rolls up over its own wider window' do
      log(create_user('later that day'), INTERVAL + 6.hours)

      Platform::ApplicationMetric.calculate_metric(app, INTERVAL)
      Platform::DailyApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, metric(Platform::ApplicationMetric).active_user_count
      assert_equal 1, metric(Platform::DailyApplicationMetric).active_user_count
    end

    ##########################################################################
    #### TotalApplicationMetric
    ####
    #### Overrides #calculate_metric to count every user up to the interval rather than the ones
    #### inside a window, and reports the same number as both counts.
    ##########################################################################

    test 'the total metric counts every user up to and including the interval' do
      join(create_user('long ago'), INTERVAL - 1.year)
      join(create_user('yesterday'), INTERVAL - 1.day)
      join(create_user('on the boundary'), INTERVAL)
      join(create_user('tomorrow'), INTERVAL + 1.day)

      Platform::TotalApplicationMetric.calculate_metric(app, INTERVAL)

      total = metric(Platform::TotalApplicationMetric)
      assert_equal 3, total.new_user_count
      assert_equal 3, total.active_user_count, 'the total metric reports the same number as both counts'
    end

    test 'the total metric is scoped to its application' do
      join(create_user('theirs'), INTERVAL - 1.day, create_app(name: 'Other'))

      Platform::TotalApplicationMetric.calculate_metric(app, INTERVAL)

      assert_equal 0, metric(Platform::TotalApplicationMetric).new_user_count
    end

    test 'user_count reads the new_user_count column' do
      total = Platform::TotalApplicationMetric.find_or_create(app, INTERVAL)
      total.update!(new_user_count: 7, active_user_count: 7)

      assert_equal 7, total.user_count
    end

    ##########################################################################
    #### Associations
    ##########################################################################

    test 'metrics are destroyed with their application' do
      Platform::ApplicationMetric.find_or_create(app, INTERVAL)
      application_id = app.id

      app.destroy

      assert_equal 0, Platform::ApplicationMetric.where(application_id: application_id).count
    end

private

    def metric(klass = Platform::ApplicationMetric)
      klass.where(application_id: app.id, interval: INTERVAL).first
    end

    def log(who, created_at, application = app)
      Platform::ApplicationLog.create!(application: application, user: who,
                                       event: 'profile.get', created_at: created_at)
    end

    def join(who, created_at, application = app)
      Platform::ApplicationUser.create!(application: application, user: who,
                                        created_at: created_at)
    end

  end # class ApplicationMetricTest
end # module Platform
