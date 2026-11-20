require 'test_helper'

class Platform::Admin::DevelopersControllerTest < Platform::ControllerTestCase

  test 'index requires an admin' do
    login_as user
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index lists the developers' do
    developer
    login_as admin_user

    get :index
    assert_response :success
    assert_includes assigned(:developers).results.to_a, developer
  end

  test 'view requires an admin' do
    login_as user
    get :view, params: {dev_id: developer.id}
    assert_redirected_to Platform::Config.default_url
  end

  test 'view' do
    developer.update!(name: 'A Developer', email: 'dev@example.com')
    login_as admin_user

    get :view, params: {dev_id: developer.id}
    assert_response :success
    assert_equal developer, assigned(:dev)
    assert_match 'A Developer', response.body
  end

  test 'lb_edit renders the edit form with no layout' do
    developer
    login_as admin_user

    get :lb_edit, params: {dev_id: developer.id}
    assert_response :success
    assert_equal developer, assigned(:dev)
    assert_select 'input#dev_name'
    assert_no_match '<html', response.body
  end

  test 'update requires an admin' do
    login_as user
    post :update, params: {dev_id: developer.id, dev: {name: 'Changed'},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
    assert_not_equal 'Changed', developer.reload.name
  end

  test 'update saves the developer' do
    developer
    login_as admin_user

    post :update, params: {dev_id: developer.id, source_url: source_url,
                           dev: {name: 'Changed', about: 'About', url: 'http://example.com',
                                 email: 'new@example.com', phone: '555'},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to source_url

    developer.reload
    assert_equal 'Changed',          developer.name
    assert_equal 'About',            developer.about
    assert_equal 'http://example.com', developer.url
    assert_equal 'new@example.com',  developer.email
    assert_equal '555',              developer.phone
  end

  # user_id is the account the developer record hangs off; moving it would move every application
  # under it too, so it is not one of the fields this form may set.
  test 'update will not reassign the developer to another account' do
    developer
    other = create_user('Someone Else')
    login_as admin_user

    post :update, params: {dev_id: developer.id, source_url: source_url,
                           dev: {name: 'Changed', user_id: other.id},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to source_url

    developer.reload
    assert_equal 'Changed', developer.name
    assert_not_equal other.id, developer.user_id
  end

  test 'update saves nothing over GET' do
    developer.update!(name: 'Original')
    login_as admin_user

    get :update, params: {dev_id: developer.id, source_url: source_url, dev: {name: 'Changed'}}
    assert_redirected_to source_url
    assert_equal 'Original', developer.reload.name
  end

  test 'update on a developer that does not exist' do
    login_as admin_user

    post :update, params: {dev_id: 0, source_url: source_url, dev: {name: 'Changed'},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
  end

private

  def source_url
    'http://test.host/platform/admin/developers'
  end

end # class Platform::Admin::DevelopersControllerTest
