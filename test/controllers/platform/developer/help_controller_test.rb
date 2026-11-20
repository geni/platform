require 'test_helper'

# The developer documentation.  Like the API Explorer it skips :validate_guest_user and
# :validate_developer -- documentation is readable before signing up -- and every action runs
# :set_version, because the API reference is versioned.
class Platform::Developer::HelpControllerTest < Platform::ControllerTestCase

  # The static pages, each of which renders _navigation and so exercises the whole sidebar: the
  # version picker, the API object list and the links to every other page in here.
  #
  # rate_limits, scopes, terms, widget_doc and widget_tree are in the list but have no method on
  # the controller -- they are templates with no action.  They render all the same, and
  # _navigation links to two of them, so a 404 here would be a broken sidebar everywhere.
  %w[index reference branding oauth_intro oauth_server_side oauth_client_side
     oauth_trusted_client oauth_app_login oauth_desktop oauth_mobile oauth_extensions
     sdk_js sdk_ios rate_limits scopes terms widget_doc widget_tree].each do |action|
    test action do
      get action.to_sym
      assert_response :success
    end
  end

  test 'index is reachable by a guest' do
    get :index
    assert_response :success
  end

  test 'set_version defaults to the configured api version' do
    get :index
    assert_not_nil Platform::Config.api_default_version
    assert_equal Platform::Config.api_default_version, assigned(:version)
  end

  test 'set_version takes the version asked for' do
    get :index, params: {version: '1.0.0'}
    assert_equal '1.0.0', assigned(:version)
  end

  ##########################################################################
  #### api -- the generated reference page
  ##########################################################################

  test 'api refuses a version it has no reference for' do
    get :api, params: {version: '0.0.1', path: '/profile'}
    assert_redirected_to action: :index, version: '0.0.1'
    assert_match 'Unsupported API version', flash[:trfe]
  end

  test 'api requires a path' do
    get :api
    assert_redirected_to action: :index, version: Platform::Config.api_default_version
    assert_match 'API path must be provided', flash[:trfe]
  end

  test 'api refuses a path the reference does not describe' do
    stub_reference

    get :api, params: {path: '/nonesuch'}
    assert_redirected_to action: :index, version: Platform::Config.api_default_version
    assert_match 'Unsupported API path', flash[:trfe]
  end

  test 'api documents an object' do
    stub_reference

    get :api, params: {path: '/profile'}
    assert_response :success
    assert_equal '/profile', assigned(:api)[:path]
  end

  # A leading slash leaves an empty first element behind when the path is split, which the action
  # drops before looking the object up.
  test 'api documents an object named without a leading slash' do
    stub_reference

    get :api, params: {path: 'profile'}
    assert_response :success
    assert_equal '/profile', assigned(:api)[:path]
  end

  # One segment and a :default_action on the object means "document that action".
  test 'api falls through to the object\'s default action' do
    stub_reference

    get :api, params: {path: '/union'}
    assert_response :success
    assert_equal '/union-partners', assigned(:api)[:path]
    assert_equal '/union', assigned(:api)[:parent][:path]
  end

  test 'api documents an action of an object' do
    stub_reference

    get :api, params: {path: '/profile/immediate-family'}
    assert_response :success
    assert_equal '/profile-immediate-family', assigned(:api)[:path]
    assert_equal '/profile', assigned(:api)[:parent][:path]
  end

  # Two segments where the object has no such action.  The action says so and renders the object
  # it did find rather than redirecting.
  test 'api reports an action the object does not have' do
    stub_reference

    get :api, params: {path: '/profile/nonesuch'}
    assert_response :success
    # On the page rather than in flash[]: the response renders, and tr8n's _flashes partial shows
    # the message and clears it on the way past.
    assert_match 'Unsupported API path', response.body
    assert_equal '/profile', assigned(:api)[:path]
  end

private

  # The API reference is host configuration -- a directory of yml files under
  # Platform::Config.api[:config_path], naming the host's own API objects -- so the gem ships
  # none and there is nothing to document without this.
  def stub_reference
    Platform::Config.stubs(:api_reference).returns(HashWithIndifferentAccess.new(
      'profile' => {
        'path'        => '/profile',
        'description' => 'A person',
        'actions'     => {
          'immediate-family' => {'path' => '/profile-immediate-family', 'description' => 'Parents, partners and children'},
        },
      },
      'union' => {
        'path'           => '/union',
        'description'    => 'A marriage or partnership',
        'default_action' => 'partners',
        'actions'        => {'partners' => {'path' => '/union-partners', 'description' => 'The two people in it'}},
      }
    ))
  end

end # class Platform::Developer::HelpControllerTest
