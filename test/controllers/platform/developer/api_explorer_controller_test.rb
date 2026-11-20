require 'test_helper'

# The API Explorer.  It skips both :validate_guest_user and :validate_developer -- it is a
# documentation tool, so a visitor who has not signed up can try the API out -- and it keeps its
# request history in a cookie rather than on the server.
class Platform::Developer::ApiExplorerControllerTest < Platform::ControllerTestCase

  test 'index is reachable by a guest' do
    get :index
    assert_response :success
  end

  test 'index' do
    login_as developer
    get :index
    assert_response :success
  end

  # #prepare_api_version, which every action in here runs.
  test 'the api version defaults to the configured one' do
    get :index
    assert_not_nil Platform::Config.api_default_version
    assert_equal Platform::Config.api_default_version, assigned(:api_version)
  end

  test 'the api version can be asked for' do
    get :index, params: {api_version: '1.0.0'}
    assert_equal '1.0.0', assigned(:api_version)
  end

  # The history cookie is handed to the page as a JSON string for its javascript to parse.
  test 'index passes the history cookie through' do
    @request.cookies['api_history'] = '[{"path":"/profile"}]'
    @request.cookies['api_history_index'] = '0'

    get :index
    assert_response :success
    assert_equal '[{"path":"/profile"}]', assigned(:api_history)
    assert_equal '0', assigned(:api_history_index)
  end

  test 'index defaults the history to an empty list' do
    get :index
    assert_equal '[]', assigned(:api_history)
    assert_equal 0,    assigned(:api_history_index)
  end

  # #history parses the same cookie, because this action renders the list rather than handing it
  # to javascript.
  test 'history parses the history cookie' do
    @request.cookies['api_history'] = '[{"path":"/profile"}]'

    get :history, params: {api_history_index: '0'}
    assert_response :success
    assert_equal [{'path' => '/profile'}], assigned(:api_history)
    assert_equal 0, assigned(:api_history_index)
  end

  test 'history with no cookie' do
    get :history
    assert_response :success
    assert_empty assigned(:api_history)
    assert_equal(-1, assigned(:api_history_index))
  end

  # explorer_groups and the API reference files are both host configuration -- they name the
  # host's own API objects -- so under the gem's own config.yml there is nothing to list.  That
  # used to be a 500 rather than an empty list: see Platform::Config.api_explorer_groups.
  test 'options with nothing configured' do
    get :options
    assert_response :success
  end

  test 'options lists the configured api objects' do
    Platform::Config.stubs(:api_explorer_groups).returns([%w[profile], %w[union]])
    Platform::Config.stubs(:api_reference).returns(HashWithIndifferentAccess.new(
      'profile' => {'path' => '/profile', 'actions' => {'immediate-family' => {'path' => '/profile-immediate-family'}}},
      'union'   => {'path' => '/union', 'method' => 'POST'}
    ))

    get :options
    assert_response :success
    assert_select 'div.api_list', 2
    assert_match 'Profile', response.body
    assert_match 'immediate-family', response.body
  end

  test 'oauth_lander' do
    get :oauth_lander
    assert_response :success
  end

end # class Platform::Developer::ApiExplorerControllerTest
