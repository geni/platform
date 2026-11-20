require 'test_helper'

# Platform::Admin::BaseController has no actions of its own, so this drives it through the
# smallest concrete subclass.  What matters here is :validate_admin -- the only thing standing in
# front of every admin screen -- and the fact that this branch of the hierarchy deliberately
# drops :validate_platform_enabled.
class Platform::Admin::BaseControllerTest < Platform::ControllerTestCase
  tests Platform::Admin::ClientsdkController

  # :validate_guest_user comes from Platform::BaseController and so runs first -- which is why a
  # guest is turned away as a guest rather than as a non-admin.
  test 'a guest is sent to the site default url' do
    get :index
    assert_redirected_to Platform::Config.default_url
    assert_match 'must be a registered user', flash[:trfe]
  end

  test 'a logged in user who is not an admin is sent to the site default url' do
    login_as user
    get :index
    assert_redirected_to Platform::Config.default_url
    assert_match 'must be an admin', flash[:trfe]
  end

  test 'an admin gets the page' do
    login_as admin_user
    get :index
    assert_response :success
  end

  # Platform::Admin::BaseController overrides #validate_platform_enabled with a no-op: turning the
  # platform off for users should not lock the admin out of the screens they would use to turn it
  # back on.
  test 'a disabled platform does not shut the admin screens' do
    Platform::Config.stubs(:disabled?).returns(true)
    login_as admin_user

    get :index
    assert_response :success
  end

  test 'platform_admin_tabs names the five admin sections' do
    login_as admin_user
    get :index

    controllers = @controller.send(:platform_admin_tabs).collect { |tab| tab['controller'] }
    assert_equal %w[apps developers categories forum metrics], controllers
  end

end # class Platform::Admin::BaseControllerTest
