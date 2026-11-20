require 'test_helper'

# Platform::Developer::BaseController has no actions of its own, so this drives it through the
# smallest concrete subclass.  What is being tested is :validate_developer -- the gate in front of
# every developer page -- and the tab list the developer layout renders from.
class Platform::Developer::BaseControllerTest < Platform::ControllerTestCase
  tests Platform::Developer::ResourcesController

  test 'a guest is sent to the site default url' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  # :validate_guest_user runs before :validate_developer, so a logged-out visitor never reaches
  # the registration redirect below.
  test 'a logged in user who is not a developer is sent to registration' do
    login_as user
    get :index
    assert_redirected_to '/platform/developer/registration'
  end

  test 'a developer gets the page' do
    login_as developer
    get :index
    assert_response :success
  end

  # The other branch of :validate_developer.  With the agreement switched off there is nothing to
  # agree to, so the viewer is registered as a developer on the spot rather than redirected.
  test 'with the developer agreement disabled a plain user is registered on the way through' do
    Platform::Config.stubs(:enable_developer_agreement?).returns(false)
    login_as user

    assert_difference 'Platform::Developer::Developer.count' do
      get :index
    end

    assert_response :success
    assert_equal user, Platform::Config.current_developer.user
  end

  test 'with the developer agreement disabled an existing developer is not registered twice' do
    Platform::Config.stubs(:enable_developer_agreement?).returns(false)
    login_as developer

    assert_no_difference 'Platform::Developer::Developer.count' do
      get :index
    end

    assert_response :success
  end

  test 'platform_developer_tabs answers the configured feature list' do
    login_as developer
    get :index

    assert_equal Platform::Config.features, @controller.send(:platform_developer_tabs)
  end

end # class Platform::Developer::BaseControllerTest
