require 'test_helper'

# The three routed pages of the public platform site, plus the two before_actions every
# Platform::BaseController subclass inherits.  HomeController skips :validate_guest_user -- it is
# the landing page a guest is sent to -- so it is the one place the :validate_platform_enabled
# branch can be reached without logging in first.
class Platform::HomeControllerTest < Platform::ControllerTestCase

  test 'index' do
    login_as user
    get :index
    assert_response :success
  end

  # The skip_before_action, which is the whole reason this controller has one.
  test 'index is reachable by a guest' do
    get :index
    assert_response :success
  end

  test 'credits' do
    get :credits
    assert_response :success
  end

  test 'license' do
    get :license
    assert_response :success
  end

  # Platform::BaseController#validate_platform_enabled.  Platform::Admin::BaseController overrides
  # it to a no-op, so this is the only place it does anything.
  test 'a disabled platform redirects to the site default url' do
    Platform::Config.stubs(:disabled?).returns(true)

    get :index
    assert_redirected_to Platform::Config.default_url
    assert_match 'rights', flash[:trfe]
  end

  # Platform::BaseController#init_platform.  It evals Platform::Config.current_user_method against
  # the controller and keeps the result only if it is a Platform::Config.user_class, so the
  # thread-local the rest of the gem reads is set from the session on every request.
  test 'init_platform publishes the session user as the platform current user' do
    login_as user

    get :index
    assert_equal user, Platform::Config.current_user
  end

  test 'init_platform leaves the platform current user a guest when nobody is logged in' do
    get :index
    assert Platform::Config.current_user_is_guest?
  end

  # The rescue in #init_platform: a host application whose current_user method raises leaves the
  # gem with no idea who the viewer is, which is not something to carry on from.
  test 'init_platform reports a current_user_method that raises' do
    Platform::Config.stubs(:current_user_method).returns('raise "boom"')

    error = assert_raises(RuntimeError) { get :index }
    assert_match 'Platform cannot be initialized', error.message
    assert_match 'boom', error.message
  end

end # class Platform::HomeControllerTest
