require 'test_helper'

# The developer's own details page.  #update_section is an in-place editor: the page asks for the
# same partial back in :edit mode, posts the form to the same action, and gets the partial back in
# :view mode.
class Platform::Developer::InfoControllerTest < Platform::ControllerTestCase

  test 'index requires a developer' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index' do
    login_as developer
    get :index
    assert_response :success
    assert_select 'div#basic_info_container'
  end

  # A GET renders the section without saving anything -- that is how the page switches a section
  # into edit mode.
  test 'update_section over GET renders the section in the mode asked for' do
    login_as developer

    get :update_section, params: {section: 'basic_info', mode: 'edit'}
    assert_response :success
    assert_select 'input#developer_name'
  end

  test 'update_section over GET can render the section in view mode' do
    login_as developer

    get :update_section, params: {section: 'basic_info', mode: 'view'}
    assert_response :success
    assert_select 'input#developer_name', false, 'view mode should not render the form fields'
  end

  test 'update_section saves the section and renders it in view mode' do
    login_as developer

    post :update_section, params: {section: 'basic_info',
                                   developer: {name: 'New Name', email: 'new@example.com',
                                               url: 'http://example.com', phone: '555',
                                               about: 'About me'},
                                   authenticity_token: form_authenticity_token}
    assert_response :success
    assert_select 'input#developer_name', false, 'the saved section comes back in view mode'

    developer.reload
    assert_equal 'New Name',         developer.name
    assert_equal 'new@example.com',  developer.email
    assert_equal 'http://example.com', developer.url
    assert_equal '555',              developer.phone
    assert_equal 'About me',         developer.about
  end

  # The attributes a developer may set are the five on the form.  user_id is not one of them:
  # assigning it would move the record onto somebody else's account.
  test 'update_section ignores attributes that are not the developer\'s to set' do
    login_as developer
    other = create_user('Someone Else')

    post :update_section, params: {section: 'basic_info',
                                   developer: {name: 'New Name', user_id: other.id},
                                   authenticity_token: form_authenticity_token}
    assert_response :success

    developer.reload
    assert_equal 'New Name', developer.name
    assert_not_equal other.id, developer.user_id
  end

end # class Platform::Developer::InfoControllerTest
