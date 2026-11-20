require 'test_helper'

# The :validate_developer branches are covered once, in
# test/controllers/platform/developer/base_controller_test.rb, which drives them through this
# controller because it is the smallest one that inherits them.
class Platform::Developer::ResourcesControllerTest < Platform::ControllerTestCase

  test 'index' do
    login_as developer
    get :index
    assert_response :success
  end

end # class Platform::Developer::ResourcesControllerTest
