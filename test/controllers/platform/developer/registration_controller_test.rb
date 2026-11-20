require 'test_helper'

# The developer agreement.  This is the one developer controller that skips :validate_developer --
# it has to, because it is where someone who is not yet a developer is sent.
class Platform::Developer::RegistrationControllerTest < Platform::ControllerTestCase

  test 'index requires login' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index is reachable by a user who is not a developer yet' do
    login_as user
    get :index
    assert_response :success
  end

  test 'proceed registers the viewer as a developer' do
    login_as user

    assert_difference 'Platform::Developer::Developer.count' do
      post :proceed, params: {authenticity_token: form_authenticity_token}
    end

    assert_redirected_to '/platform/developer/apps/new'
    assert_equal user, Platform::Developer::Developer.order('id desc').first.user
  end

  test 'proceed leaves an existing developer alone' do
    login_as developer

    assert_no_difference 'Platform::Developer::Developer.count' do
      post :proceed, params: {authenticity_token: form_authenticity_token}
    end

    assert_redirected_to '/platform/developer/apps/new'
  end

  # The action only registers on POST, so a GET cannot be used to accept the agreement on the
  # viewer's behalf -- a link or an image tag would be enough otherwise.
  test 'proceed does not register over GET' do
    login_as user

    assert_no_difference 'Platform::Developer::Developer.count' do
      get :proceed
    end

    assert_redirected_to '/platform/developer/apps/new'
  end

end # class Platform::Developer::RegistrationControllerTest
