require 'test_helper'

class DummyControllerTest < ActionDispatch::IntegrationTest

# Doesn't work
  test "index" do
    get '/'
    assert_response :success
    assert_select 'h1', 'Platform Stuff'
    assert_select 'h1', 'Tr8n Stuff'
  end

end
