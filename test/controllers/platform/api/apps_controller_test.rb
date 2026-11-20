require 'test_helper'

# The gem's only API endpoint, and with it the whole Platform::Api::BaseController request cycle:
# the format default, the enabled and blocked checks, bearer and cookie authentication, the JSON
# envelope and the call log.
#
# The companion file, test/controllers/platform/api/base_controller_test.rb, covers the pieces of
# Platform::Api::BaseController whose contract is with their caller rather than with a response --
# #render_exception and the pagination and time helpers -- as unit tests.
#
# Nothing here rescues: this gem renders API errors (#render_exception) but the `rescue_from` that
# calls it belongs to the host application, so an error escapes the controller and these tests
# assert on the exception.
class Platform::Api::AppsControllerTest < Platform::ControllerTestCase

  # Every test here identifies itself somehow, because an unidentified caller is turned away:
  # api[:public_enabled] ships off.  See "an anonymous call is sent to login" below.
  def setup
    super
    login_as user
  end

  test 'index answers json without being asked' do
    app

    get :index
    assert_response :success
    assert_equal 'application/json', @response.media_type
  end

  test 'index lists the applications' do
    app

    get :index
    assert_response :success
    assert_match app.name, response.body
  end

  ##########################################################################
  #### ensure_api_enabled
  ##########################################################################

  test 'a disabled api is unavailable' do
    Platform::Config.stubs(:enable_api?).returns(false)

    error = assert_raises(Platform::Api::BaseController::ServiceUnavailableError) { get :index }
    assert_equal :service_unavailable, error.status
  end

  test 'a blocked application is refused' do
    app.approve!
    app.block!
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'blocked-app-token')

    error = assert_raises(Platform::Api::BaseController::ForbiddenError) do
      get :index, params: {access_token: token.token}
    end
    assert_equal :forbidden, error.status
    assert_match 'blocked', error.message
  end

  ##########################################################################
  #### authenticate
  ##########################################################################

  test 'a bearer token identifies the caller' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'bearer-token')
    @request.headers['Authorization'] = "Bearer #{token.token}"

    get :index
    assert_response :success
    assert_equal user, Platform::Config.current_user
  end

  test 'an access_token parameter identifies the caller' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'param-token')

    get :index, params: {access_token: token.token}
    assert_response :success
    assert_equal user, Platform::Config.current_user
  end

  test 'an oauth_token parameter identifies the caller' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'legacy-token')

    get :index, params: {oauth_token: token.token}
    assert_response :success
    assert_equal user, Platform::Config.current_user
  end

  # An Authorization header in some other scheme is not an OAuth attempt at all, so it is not a
  # failed one either -- the call carries on as an anonymous one.
  test 'a non-bearer Authorization header is not an oauth attempt' do
    @request.headers['Authorization'] = 'Basic Zm9vOmJhcg=='

    get :index
    assert_response :success
  end

  # A token that has expired, been revoked, or never existed.  UnauthorizedError rather than a
  # bare Exception is what lets the host's rescue_from turn this into the documented 401.
  test 'a token that identifies nothing is unauthorized' do
    error = assert_raises(Platform::Api::BaseController::UnauthorizedError) do
      get :index, params: {access_token: 'not-a-token'}
    end

    assert_equal :unauthorized, error.status
    assert_match 'Invalid access token', error.message
  end

  test 'an invalidated token is unauthorized' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'revoked-token')
    token.invalidate!

    assert_raises(Platform::Api::BaseController::UnauthorizedError) do
      get :index, params: {access_token: token.token}
    end
  end

  test 'an anonymous call is allowed when the api is public' do
    Platform::Config.stubs(:enable_public_api?).returns(true)
    logout

    get :index
    assert_response :success
  end

  # Which is what a caller with no credentials gets under the shipped configuration.
  test 'an anonymous call is sent to login when the api is not public' do
    logout

    get :index
    assert_redirected_to Platform::Config.login_url
  end

  # The switch now has a reader.  config.yml spelled it allow_public while
  # #enable_public_api? read public_enabled -- both written in the same commit -- so the setting
  # had no reader at all and the predicate was nil for every host.  Renamed to the spelling the
  # code uses and shipped off, which is what nil already meant: turning it on decides whether
  # every API controller in the host application answers callers it cannot identify.
  test 'the public api switch is read from the configuration and ships off' do
    assert_equal false, Platform::Config.api[:public_enabled]
    assert_equal false, Platform::Config.enable_public_api?
    assert_not Platform::Config.api.key?(:allow_public), 'the old spelling should be gone'
  end

  test 'the public api switch is what opens the api to an unidentified caller' do
    logout

    public_api = Platform::Config.api.merge(public_enabled: true)
    Platform::Config.stubs(:api).returns(public_api)

    get :index
    assert_response :success
  end

  # #authenticate_via_cookie is documented as the hook a host application overrides, but the
  # gem's own version has to work: it is what lets a signed-in browser call the API without a
  # token, and it runs on every API request.
  test 'a session cookie identifies the caller' do
    get :index
    assert_response :success
    assert_equal user, Platform::Config.current_user
  end

  test 'cookie authentication is skipped when it is switched off' do
    Platform::Config.stubs(:api_cookies_enabled?).returns(false)
    Platform::Config.stubs(:enable_public_api?).returns(true)

    get :index
    assert_response :success
    assert_nil Platform::Config.current_user
  end

  # jsonp is a cross-origin mechanism, so honouring the viewer's session cookie on one would let
  # any page that can include a script tag read the viewer's data.
  test 'cookie authentication is skipped for a jsonp call' do
    Platform::Config.stubs(:enable_public_api?).returns(true)

    get :index, params: {callback: 'cb'}, xhr: true
    assert_nil Platform::Config.current_user
  end

  ##########################################################################
  #### The response envelope
  ####
  #### #render_response wraps an Array in a results envelope with page links.  Reached by handing
  #### it one: #index passes Platform::Application.all, which is a relation and goes out as a bare
  #### list.
  ##########################################################################

  test 'a list is wrapped in a results envelope' do
    Platform::Application.stubs(:all).returns([app])

    get :index
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body['results'].size
    assert_nil body['page'], 'the first short page needs no page number'
  end

  test 'a full page carries its number and a link to the next one' do
    Platform::Application.stubs(:all).returns([app])
    Platform::Config.stubs(:api_max_models).returns(1)

    get :index
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body['page']
    assert_match 'page=2', body['next_page']
    assert_nil body['previous_page']
  end

  test 'a later page carries a link back' do
    Platform::Application.stubs(:all).returns([app])
    Platform::Config.stubs(:api_max_models).returns(1)

    get :index, params: {page: '2'}
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body['page']
    assert_match 'page=1', body['previous_page']
    assert_match 'page=3', body['next_page']
  end

  # render's :text option went away in Rails 5, so ?format=xml rendered nothing and fell through
  # to an implicit render of a template no API action has.  ActiveRecord#to_xml went the same way
  # -- into activemodel-serializers-xml, which the gem now depends on -- so even once the render
  # worked, XmlMini had no serializer to call and every element held the model's #to_s.
  test 'index answers xml when it is asked for' do
    app

    get :index, params: {format: 'xml'}
    assert_response :success
    assert_equal 'application/xml', @response.media_type
    assert_match '<?xml version="1.0"', response.body
    assert_match '<applications type="array">', response.body
  end

  test 'the xml carries the applications\' attributes' do
    app

    get :index, params: {format: 'xml'}
    assert_select 'applications > application' do
      assert_select 'name', app.name
      assert_select 'key',  app.key
      assert_select 'id',   app.id.to_s
    end
  end

  # An element name cannot contain a slash, and Platform::Application underscores to
  # "platform/application" -- so the root tag used to be <platform/applications>.
  test 'the xml root is a legal element name' do
    assert_equal 'applications', @controller.send(:xml_root)
  end

  ##########################################################################
  #### The client secret
  ####
  #### #index is render_response(Platform::Application.all), so this endpoint hands every
  #### registered application's attributes to whoever asked -- and `secret` was among them, which
  #### let any API caller read every application's OAuth client secret and then impersonate it on
  #### the token endpoint.  Excluded in Platform::Application#serializable_hash, so it covers
  #### both formats.
  ##########################################################################

  test 'the json does not carry the client secret' do
    app

    get :index
    assert_response :success
    assert_match app.name, response.body
    assert_no_match app.secret, response.body
  end

  test 'the xml does not carry the client secret' do
    app

    get :index, params: {format: 'xml'}
    assert_response :success
    assert_match app.name, response.body
    assert_no_match app.secret, response.body
  end

  # #render_response builds its serializer options by merging the request's params, so a caller
  # can name :only and :except -- and ActiveModel lets :only win over :except.  Asking for the
  # one withheld attribute by name gets nothing.
  test 'a caller cannot ask for the client secret by name' do
    app

    get :index, params: {only: 'secret'}
    assert_response :success
    assert_no_match app.secret, response.body
  end

  test 'a caller cannot ask for the client secret by name in xml either' do
    app

    get :index, params: {only: 'secret', format: 'xml'}
    assert_response :success
    assert_no_match app.secret, response.body
  end

  # The public client_id, which RFC 6749 section 2.2 says is not secret -- a client sends it in
  # the clear on every authorize request.
  test 'the client_id is still published' do
    app

    get :index
    assert_match app.key, response.body
  end

  ##########################################################################
  #### jsonp
  ##########################################################################

  # render's :text option went away in Rails 5, so this rendered nothing and the request fell
  # through to an implicit render of a template no API action has.
  test 'a jsonp call is wrapped in its callback' do
    Platform::Config.stubs(:enable_public_api?).returns(true)
    app

    get :index, params: {callback: 'myCallback'}, xhr: true
    assert_response :success
    assert_equal 'application/javascript', @response.media_type
    assert_match(/\AmyCallback\(/, response.body)
    assert_match app.name, response.body
  end

  # Which is the point of the mechanism, and what Rails refuses: a javascript response to a
  # non-XHR GET is how XSSI reads a logged-in viewer's data from another origin.  Asserted so it
  # is on the record -- jsonp needs the host application to opt out of that protection for these
  # actions, and until it does the endpoint answers an error rather than data.
  test 'a jsonp call from a script tag is refused' do
    Platform::Config.stubs(:enable_public_api?).returns(true)

    assert_raises ActionController::InvalidCrossOriginRequest do
      get :index, params: {callback: 'myCallback'}
    end
  end

  ##########################################################################
  #### log_api_call
  ##########################################################################

  test 'a call is written to the application log' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'logged-token')

    assert_difference 'Platform::ApplicationLog.count' do
      get :index, params: {access_token: token.token}
    end

    log = Platform::ApplicationLog.order('id desc').first
    assert_equal app, log.application
    assert_equal user.id, log.user_id
    assert_equal 'platform/api/apps-index', log.event
    assert_equal 'GET', log.request_method
  end

  # user_id is nullable, so a token that has no user behind it -- a client_credentials token --
  # still gets a log line.  That is what Platform::ApplicationLog's `belongs_to :user, optional:
  # true` is for.
  test 'a call with no user behind the token is still logged' do
    token = Platform::Oauth::ClientToken.create!(application: app, token: 'client-token')
    logout # the token is the only credential; a session cookie would put a user on the log line

    assert_difference 'Platform::ApplicationLog.count' do
      get :index, params: {access_token: token.token}
    end

    log = Platform::ApplicationLog.order('id desc').first
    assert_nil log.user_id
    assert_equal app, log.application
  end

  # The application is not optional -- see the reasoning on
  # test/models/platform/application_log_test.rb -- and an anonymous call has no application to
  # name, so there is nothing to write.  #log_api_call uses .create rather than .create!, so this
  # is a silent no-op rather than an error on the way out of a successful response.
  test 'an anonymous call is not logged, because it names no application' do
    Platform::Config.stubs(:enable_public_api?).returns(true)
    logout

    assert_no_difference 'Platform::ApplicationLog.count' do
      get :index
    end

    assert_response :success
  end

  test 'nothing is logged when api logging is off' do
    Platform::Config.stubs(:enable_api_log?).returns(false)

    assert_no_difference 'Platform::ApplicationLog.count' do
      get :index
    end
  end

end # class Platform::Api::AppsControllerTest
