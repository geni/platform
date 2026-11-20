require 'test_helper'

# The developer's landing page.  Which applications it charts is a session preference, seeded from
# the developer's five most recent applications on the first visit and edited through #settings /
# #update_section.
class Platform::Developer::DashboardControllerTest < Platform::ControllerTestCase

  test 'index requires a developer' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index with no applications' do
    login_as developer
    get :index
    assert_response :success
  end

  test 'index with an application' do
    login_as developer
    app.approve!

    get :index
    assert_response :success
    assert_match app.name, response.body
  end

  # First visit: nothing selected yet, so the page picks the developer's own applications and
  # remembers them.
  test 'index seeds the session preference from the developer\'s own applications' do
    login_as developer
    app

    get :index
    assert_equal [app.id], session[:platform_dashboard_apps]
    assert_equal [app], assigned(:apps).to_a
  end

  test 'index charts the applications the session already names' do
    login_as developer
    first  = app
    second = create_app(name: 'Second')

    get :index, params: {}, session: {platform_dashboard_apps: [second.id]}
    assert_equal [second], assigned(:apps).to_a
    assert_not_includes assigned(:apps).to_a, first
  end

  # The session preference is not a capability: an id in it that belongs to another developer is
  # filtered out by the developer_id condition rather than charted.
  test 'index will not chart another developer\'s application' do
    other_app = create_app(developer: developer(create_user('Other Developer')))
    login_as developer

    get :index, params: {}, session: {platform_dashboard_apps: [other_app.id]}
    assert_empty assigned(:apps).to_a
  end

  test 'settings' do
    login_as developer
    app

    get :settings
    assert_response :success
    assert_match app.name, response.body
  end

  test 'update_section over GET renders the section in the mode asked for' do
    login_as developer
    app

    get :update_section, params: {section: 'apps_info', mode: 'edit'}
    assert_response :success
    assert_select "input[type=checkbox][name=?]", app.id.to_s
  end

  test 'update_section stores the chosen applications in the session' do
    login_as developer
    first  = app
    second = create_app(name: 'Second')

    post :update_section, params: {section: 'apps_info', second.id.to_s => 'checked',
                                   authenticity_token: form_authenticity_token}
    assert_response :success

    assert_equal [second.id.to_s], session[:platform_dashboard_apps]
    assert_not_includes session[:platform_dashboard_apps], first.id.to_s
  end

  # :section is the partial to render, and :controller and :action are routing, so none of the
  # three is an application id.
  test 'update_section does not mistake its own parameters for application ids' do
    login_as developer

    post :update_section, params: {section: 'apps_info', authenticity_token: form_authenticity_token}
    assert_response :success

    assert_empty session[:platform_dashboard_apps]
  end

end # class Platform::Developer::DashboardControllerTest
