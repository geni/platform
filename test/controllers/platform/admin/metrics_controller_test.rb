require 'test_helper'

# The four metric lists.  Each is a will_filter list and nothing else, so what these cover is that
# the four filter classes resolve their model and columns and that the lists render -- none of
# which is checked anywhere until the screen is opened.
class Platform::Admin::MetricsControllerTest < Platform::ControllerTestCase

  INTERVAL = Time.utc(2026, 1, 1, 12, 0, 0)

  test 'index requires an admin' do
    login_as user
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index lists the application metrics' do
    metric = Platform::ApplicationMetric.create!(application: app, interval: INTERVAL,
                                                 active_user_count: 3, new_user_count: 1)
    login_as admin_user

    get :index
    assert_response :success
    assert_includes assigned(:metrics).results.to_a, metric
  end

  # The four interval widths are separate STI subclasses of one table, and this list is all of
  # them -- the :type column in the view is there to tell them apart.
  test 'index lists the rolled up metrics as well' do
    daily = Platform::DailyApplicationMetric.create!(application: app, interval: INTERVAL,
                                                     active_user_count: 9)
    login_as admin_user

    get :index
    assert_includes assigned(:metrics).results.to_a, daily
    assert_match 'Platform::DailyApplicationMetric', response.body
  end

  test 'usage requires an admin' do
    login_as user
    get :usage
    assert_redirected_to Platform::Config.default_url
  end

  test 'usage lists the usage metrics' do
    metric = Platform::ApplicationUsageMetric.find_or_create(app, INTERVAL, 'profile.get')
    login_as admin_user

    get :usage
    assert_response :success
    assert_includes assigned(:metrics).results.to_a, metric
  end

  test 'application_log requires an admin' do
    login_as user
    get :application_log
    assert_redirected_to Platform::Config.default_url
  end

  test 'application_log lists the api calls' do
    log = Platform::ApplicationLog.create!(application: app, user: user, event: 'profile.get')
    login_as admin_user

    get :application_log
    assert_response :success
    assert_includes assigned(:logs).results.to_a, log
  end

  test 'rollup_log requires an admin' do
    login_as user
    get :rollup_log
    assert_redirected_to Platform::Config.default_url
  end

  test 'rollup_log lists the rollup runs' do
    log = Platform::RollupLog.create!(interval: INTERVAL, started_at: INTERVAL,
                                      finished_at: INTERVAL + 1.minute)
    login_as admin_user

    get :rollup_log
    assert_response :success
    assert_includes assigned(:logs).results.to_a, log
  end

end # class Platform::Admin::MetricsControllerTest
