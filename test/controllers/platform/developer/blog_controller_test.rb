require 'test_helper'

class Platform::Developer::BlogControllerTest < Platform::ControllerTestCase

  test 'index requires a developer' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index' do
    login_as developer
    get :index
    assert_response :success
  end

end # class Platform::Developer::BlogControllerTest
