require 'test_helper'

# A test harness page for the host application's JS SDK.  The :validate_admin branches are covered
# once, in test/controllers/platform/admin/base_controller_test.rb, which drives them through this
# controller because it is the smallest one that inherits them.
class Platform::Admin::ClientsdkControllerTest < Platform::ControllerTestCase

  test 'index' do
    login_as admin_user
    get :index
    assert_response :success
    assert_match 'Geni Connect', response.body
  end

end # class Platform::Admin::ClientsdkControllerTest
