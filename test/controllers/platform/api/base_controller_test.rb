require 'test_helper'

# Covers the three things on Platform::Api::BaseController that Rails 5-7 broke and that nothing in
# this gem's suite reached, because its only API subclass -- Platform::Api::AppsController -- is not
# routed in config/routes.rb.  That is why all three were found from a host app instead.
#
# These are unit tests on purpose: there is no route to drive a request through, and the contract
# each one has is with its caller rather than with a response body.
class Platform::Api::BaseControllerTest < Platform::ControllerTestCase
  tests Platform::Api::AppsController

  ForbiddenError    = Platform::Api::BaseController::ForbiddenError
  UnauthorizedError = Platform::Api::BaseController::UnauthorizedError
  BadRequestError   = Platform::Api::BaseController::BadRequestError

  ##########################################################################
  #### render_exception -- the API's error envelope
  ##########################################################################

  test 'render_exception answers an ApiError with its own status and message' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'no entry'}},
      status: :forbidden
    )

    @controller.send(:render_exception, ForbiddenError.new('no entry'))
  end

  test 'render_exception retypes an UnauthorizedError as an OAuthException' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'OAuthException', 'message' => 'Invalid access token'}},
      status: :unauthorized
    )

    @controller.send(:render_exception, UnauthorizedError.new('Invalid access token'))
  end

  test 'render_exception answers a RecordNotFound as 404 without leaking the message' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'Not Found'}},
      status: :not_found
    )

    @controller.send(:render_exception, ActiveRecord::RecordNotFound.new("Couldn't find Profile with id 7"))
  end

  test 'render_exception answers an unexpected exception as a 500' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'kaboom'}},
      status: :internal_server_error
    )

    @controller.send(:render_exception, RuntimeError.new('kaboom'))
  end

  test 'render_exception clears only_list so the envelope is not wrapped in an array' do
    params = {only_list: '1'}
    @controller.stubs(:params).returns(params)
    @controller.stubs(:render_response)

    @controller.send(:render_exception, BadRequestError.new('bad'))

    assert_nil params[:only_list]
  end

  # This gem renders API errors and does not log them -- a6f7aa5's intent.  The host app owns the
  # `rescue_from` that calls #render_exception and whatever logging it wants in front of it, so
  # neither a logger nor a logging policy should reappear here.
  test 'the gem renders API errors without logging them' do
    %i[log_exception should_log_error?].each do |name|
      assert_not @controller.respond_to?(name, true),
                 "#{name} is the host app's; exception logging does not belong in this gem"
    end

    assert @controller.respond_to?(:render_exception, true)
  end

  ##########################################################################
  #### parse_time / end_time -- Rails 7 removed to_s's format argument
  ##########################################################################

  test 'parse_time renders a timestamp in the :db format' do
    assert_equal '2026-03-04 05:06:07', @controller.send(:parse_time, '2026-03-04 05:06:07', 'unused')
  end

  # to_fs(:db) would answer the UTC instant here.  These strings are interpolated into SQL against
  # :local columns by #time_clause, so the wall clock has to survive the round trip.
  test 'parse_time keeps the local wall clock rather than converting to UTC' do
    parsed = @controller.send(:parse_time, '2026-07-04 23:30:00', 'unused')

    assert_equal '2026-07-04 23:30:00', parsed
    assert_not_equal Time.parse('2026-07-04 23:30:00').utc.strftime('%Y-%m-%d %H:%M:%S'), parsed,
                     'a UTC rendering would shift the window by the zone offset'
  end

  test 'parse_time answers the default for nil' do
    assert_equal 'the-default', @controller.send(:parse_time, nil, 'the-default')
  end

  test 'parse_time understands today and yesterday' do
    assert_equal Date.today.to_s,     @controller.send(:parse_time, 'today',     'unused')
    assert_equal Date.yesterday.to_s, @controller.send(:parse_time, 'YESTERDAY', 'unused')
  end

  test 'end_time defaults to tomorrow' do
    @controller.stubs(:params).returns({})

    assert_equal Date.tomorrow.to_s, @controller.send(:end_time)
  end

  # The pair a host app's #time_clause interpolates into SQL (`time_clause` itself is the host's
  # extension, not this class's).
  test 'start_time and end_time answer the window the caller asked for' do
    @controller.stubs(:params).returns({since: '2026-01-02', until: '2026-01-03'})

    assert_equal '2026-01-02 00:00:00', @controller.send(:start_time)
    assert_equal '2026-01-03 00:00:00', @controller.send(:end_time)
  end

  test 'start_time defaults to the start of the archive' do
    @controller.stubs(:params).returns({})

    assert_equal '2007-01-01', @controller.send(:start_time)
  end

  ##########################################################################
  #### prev_page_url / next_page_url -- params is not a Hash on Rails 5+
  ##########################################################################

  # params.merge(...) answers ActionController::Parameters, and url_for calls #to_h on it, which
  # raises ActionController::UnfilteredParameters -- so any paginated response carrying a page link
  # was a 500.  Asserting url_for is handed a real Hash is what pins the fix: Parameters is not one.
  test 'prev_page_url hands url_for a Hash rather than Parameters' do
    @controller.stubs(:params).returns(ActionController::Parameters.new(page: '3', fields: 'name'))
    @controller.stubs(:page).returns(3)

    @controller.expects(:url_for).with do |given|
      given.is_a?(Hash) && !given.is_a?(ActionController::Parameters) &&
        given['fields'] == 'name' && given[:page] == 2
    end

    @controller.send(:prev_page_url)
  end

  test 'next_page_url hands url_for a Hash rather than Parameters' do
    @controller.stubs(:params).returns(ActionController::Parameters.new(page: '3', fields: 'name'))
    @controller.stubs(:page).returns(3)

    @controller.expects(:url_for).with do |given|
      given.is_a?(Hash) && !given.is_a?(ActionController::Parameters) && given[:page] == 4
    end

    @controller.send(:next_page_url)
  end

  ##########################################################################
  #### ApiError
  ##########################################################################

  # The status comes from the class name, so a subclass does not have to declare one.
  test 'each error answers the status its name spells' do
    assert_equal :bad_request,           BadRequestError.new.status
    assert_equal :forbidden,             ForbiddenError.new.status
    assert_equal :unauthorized,          UnauthorizedError.new.status
    assert_equal :method_not_allowed,    Platform::Api::BaseController::MethodNotAllowedError.new.status
    assert_equal :service_unavailable,   Platform::Api::BaseController::ServiceUnavailableError.new.status
  end

  # #init_cause wraps the exception that actually went wrong, and #message then answers that one's
  # message -- so an error raised in a lower layer keeps its own text in the API envelope.
  test 'init_cause takes over the message and answers itself for chaining' do
    error = BadRequestError.new('outer')
    assert_same error, error.init_cause(ArgumentError.new('the real problem'))
    assert_equal 'the real problem', error.message
  end

  test 'an error with no cause keeps its own message' do
    assert_equal 'outer', BadRequestError.new('outer').message
  end

  test 'the routine errors are named for a host that wants to skip logging them' do
    expected = [ActionController::MethodNotAllowed, ActiveRecord::RecordNotFound, ForbiddenError,
                Platform::Api::BaseController::MethodNotAllowedError,
                Platform::Api::BaseController::ServiceUnavailableError, UnauthorizedError]
    assert_equal expected, Platform::Api::BaseController::PLATFORM_NON_LOGGED_EXCEPTIONS
  end

  # The one error class #render_exception maps without going through ApiError#status.
  test 'render_exception answers a StatementInvalid as a 400 without leaking the sql' do
    @controller.stubs(:params).returns({})

    @controller.expects(:render_response).with(
      {'error' => {'type' => 'ApiException', 'message' => 'Bad Request'}},
      status: :bad_request
    )

    @controller.send(:render_exception, ActiveRecord::StatementInvalid.new('PG::SyntaxError: SELECT ...'))
  end

  ##########################################################################
  #### ssl_required?
  ##########################################################################

  # A call with no client application behind it is not held to SSL, which is what lets the public
  # API answer an anonymous http call.
  test 'ssl is not required of a call with no client application' do
    @controller.stubs(:client_app).returns(nil)

    assert_equal false, @controller.send(:ssl_required?)
  end

  test 'ssl is not required in development or test' do
    @controller.stubs(:client_app).returns(Object.new)

    assert_equal false, @controller.send(:ssl_required?)
  end

  ##########################################################################
  #### Paging
  ##########################################################################

  test 'page defaults to the first page' do
    @controller.stubs(:params).returns({})
    assert_equal 1, @controller.send(:page)
  end

  test 'page takes the page asked for' do
    @controller.stubs(:params).returns(page: '4')
    assert_equal 4, @controller.send(:page)
  end

  test 'limit defaults to the configured maximum' do
    @controller.stubs(:params).returns({})
    assert_equal Platform::Config.api_max_models, @controller.send(:limit)
  end

  test 'limit takes the size asked for' do
    @controller.stubs(:params).returns(limit: '5')
    assert_equal 5, @controller.send(:limit)
  end

  # An application without the unlimited_models flag cannot ask for more than the configured
  # maximum, however large a limit it sends.
  test 'limit is capped at the configured maximum' do
    @controller.stubs(:params).returns(limit: '10000')
    @controller.stubs(:client_app).returns(nil)

    assert_equal Platform::Config.api_max_models, @controller.send(:limit)
  end

  test 'an application with the unlimited_models flag is not capped' do
    app = Platform::Application.new
    app.allow_unlimited_models
    @controller.stubs(:params).returns(limit: '10000')
    @controller.stubs(:client_app).returns(app)

    assert_equal 10000, @controller.send(:limit)
  end

  test 'offset is worked out from the page and the limit' do
    @controller.stubs(:params).returns(page: '3', limit: '10')
    assert_equal 20, @controller.send(:offset)
  end

  test 'offset can be given directly' do
    @controller.stubs(:params).returns(offset: '7')
    assert_equal 7, @controller.send(:offset)
  end

  ##########################################################################
  #### all? / jsonp? / xml_root
  ##########################################################################

  # String#param_true? was a Rails 2-era monkey patch in the host application and exists nowhere
  # here, so this was a NoMethodError for any subclass that asked.
  test 'all? reads the parameter as a boolean' do
    [['true', true], ['1', true], ['yes', true], ['false', false], ['0', false],
     ['', false], [nil, false]].each do |given, expected|
      @controller.stubs(:params).returns(all: given)
      assert_equal expected, @controller.send(:all?), "all=#{given.inspect}"
    end
  end

  test 'jsonp? is true only when a callback is named' do
    @controller.stubs(:params).returns(callback: 'cb')
    assert @controller.send(:jsonp?)

    @controller.stubs(:params).returns(callback: '')
    assert_not @controller.send(:jsonp?)

    @controller.stubs(:params).returns({})
    assert_not @controller.send(:jsonp?)
  end

  # Demodulized, because an XML element name cannot contain a slash -- see #xml_root.
  test 'xml_root is the model name pluralized' do
    assert_equal 'applications', @controller.send(:xml_root)
  end

  ##########################################################################
  #### ids / page_models / page_model
  ####
  #### The lookup helpers a subclass's actions are built from.  Neither the gem's own
  #### Platform::Api::AppsController nor anything else in here calls them, which is why all three
  #### carried Rails 2 code: the finder option hash Rails 4 removed, and an Array#apply monkey
  #### patch that has never existed in this gem.
  ##########################################################################

  test 'ids reads a comma separated list from either parameter' do
    @controller.stubs(:params).returns(id: '3,1', ids: '2')

    assert_equal [3, 1, 2], @controller.send(:ids)
  end

  test 'ids are integers, uniqued' do
    @controller.stubs(:params).returns(id: '3,3,4')

    assert_equal [3, 4], @controller.send(:ids)
  end

  test 'ids falls back to the subclass\'s default models' do
    @controller.stubs(:params).returns({})
    @controller.stubs(:default_model_ids).returns([9])

    assert_equal [9], @controller.send(:ids)
  end

  test 'page_model_conditions names the ids' do
    @controller.stubs(:params).returns(id: '5')

    assert_equal({id: [5]}, @controller.send(:page_model_conditions))
  end

  test 'id_fields are :id and :ids' do
    assert_equal [:id, :ids], Platform::Api::BaseController.id_fields
  end

  test 'page_models answers the window the request asked for' do
    first  = create_app(name: 'First')
    second = create_app(name: 'Second')
    @controller.stubs(:params).returns(ids: "#{first.id},#{second.id}", limit: '1', page: '2')
    @controller.stubs(:client_app).returns(nil)

    assert_equal [second], @controller.send(:page_models).to_a
  end

  test 'page_model answers the one model named' do
    wanted = create_app(name: 'Wanted')
    @controller.stubs(:params).returns(id: wanted.id.to_s)

    assert_equal wanted, @controller.send(:page_model)
  end

  test 'page_model answers RecordNotFound when the id names nothing' do
    @controller.stubs(:params).returns(id: '0')

    assert_raises ActiveRecord::RecordNotFound do
      @controller.send(:page_model)
    end
  end

  # Both are the subclass's to provide, and saying so is the whole content of the base versions.
  test 'model_class and default_models have to be implemented by the subclass' do
    base = Platform::Api::BaseController.new

    %i[model_class default_models].each do |name|
      error = assert_raises(Exception) { base.send(name) }
      assert_match 'must be implemented', error.message
    end
  end

  ##########################################################################
  #### Rate limits
  ##########################################################################

  test 'the cache key is per user for a logged in caller' do
    Platform::Config.init(user)

    assert_equal "api_rate_limit_u_#{user.id}", @controller.send(:cache_key)
  end

  test 'the cache key is per ip for a caller we cannot identify' do
    Platform::Config.reset!
    @controller.stubs(:request).returns(stub(ip: '10.0.0.1'))

    assert_equal 'api_rate_limit_ip_10.0.0.1', @controller.send(:cache_key)
  end

  # No client application means an anonymous caller, who is always rate limited; an application
  # with the no_rate_limit flag is not.
  test 'a call with no client application is rate limited' do
    @controller.stubs(:client_app).returns(nil)
    assert @controller.send(:rate_limited?)
  end

  test 'an application with the no_rate_limit flag is not rate limited' do
    app = Platform::Application.new
    app.rate_limited(false)
    @controller.stubs(:client_app).returns(app)

    assert_not @controller.send(:rate_limited?)
  end

  test 'check_rate_limit starts a window on the first call' do
    Platform::Config.init(user)
    @controller.stubs(:request_count).returns(nil)

    Platform::Cache.expects(:set).with("api_rate_limit_u_#{user.id}", '1',
                                       expiry: Platform::Config.api_request_window, raw: true)

    @controller.send(:check_rate_limit)
  end

  test 'check_rate_limit counts a call inside the window' do
    Platform::Config.init(user)
    @controller.stubs(:request_count).returns(1)

    Platform::Cache.expects(:increment).with("api_rate_limit_u_#{user.id}")

    @controller.send(:check_rate_limit)
  end

  test 'check_rate_limit refuses a call over the limit' do
    Platform::Config.init(user)
    @controller.stubs(:request_count).returns(Platform::Config.api_request_limit)

    error = assert_raises(ForbiddenError) { @controller.send(:check_rate_limit) }
    assert_match 'Rate limit exceeded', error.message
  end

  test 'check_rate_limit does nothing for a caller that is not rate limited' do
    @controller.stubs(:rate_limited?).returns(false)
    Platform::Cache.expects(:set).never
    Platform::Cache.expects(:increment).never

    assert_nil @controller.send(:check_rate_limit)
  end

  ##########################################################################
  #### api_version / the response structure check
  ##########################################################################

  test 'api_version takes the version asked for' do
    @controller.stubs(:params).returns(api_version: '1.0.0')

    assert_equal '1.0.0', @controller.send(:api_version)
  end

  test 'api_version falls back to the application\'s own version, then to the default' do
    app = Platform::Application.new(api_version: '1.0.0')
    @controller.stubs(:params).returns({})
    @controller.stubs(:client_app).returns(app)
    assert_equal '1.0.0', @controller.send(:api_version)

    @controller.instance_variable_set(:@api_version, nil)
    @controller.stubs(:client_app).returns(nil)
    assert_equal Platform::Config.api_default_version, @controller.send(:api_version)
  end

  test 'api_reference_for_path finds an object and an action under it' do
    ref = HashWithIndifferentAccess.new(
      'profile' => {'path' => '/profile',
                    'actions' => {'immediate-family' => {'path' => '/profile-immediate-family'}}}
    )

    assert_equal '/profile', @controller.send(:api_reference_for_path, ref, 'profile')['path']
    assert_equal '/profile-immediate-family',
                 @controller.send(:api_reference_for_path, ref, 'profile/immediate-family')['path']
  end

  test 'api_reference_for_path answers nothing for a path it does not describe' do
    ref = HashWithIndifferentAccess.new('profile' => {'path' => '/profile'})

    assert_nil @controller.send(:api_reference_for_path, ref, 'nonesuch')
    assert_nil @controller.send(:api_reference_for_path, ref, 'profile/nonesuch')
    assert_nil @controller.send(:api_reference_for_path, ref, 'nonesuch/nonesuch')
  end

  # Off by default, and the gem ships no reference files, so the check has to stay out of the way.
  test 'the response structure check does nothing while verification is off' do
    assert_not Platform::Config.enable_api_verification?
    assert_nil @controller.send(:validate_response_structure, '{"name":"anything"}')
  end

  ##########################################################################
  #### CORS
  ####
  #### None of this had ever executed.  #cors_preflight_check compared request.method -- the
  #### string "OPTIONS" -- with :options, so its body was unreachable, and
  #### #cors_set_access_control_headers had no caller at all, so no response carried the headers
  #### a browser actually checks.  Both are repaired and both are gated on api[:cors_enabled],
  #### which ships off: see the note on that key in config/platform/config.yml.
  ##########################################################################

  test 'cors is off under the shipped configuration' do
    assert_equal false, Platform::Config.api[:cors_enabled]
    assert_equal false, Platform::Config.api_cors_enabled?
    assert_not @controller.send(:cors_enabled?)
  end

  test 'an OPTIONS request is not answered as a preflight while cors is off' do
    process :index, method: 'OPTIONS'

    assert_nil @response.headers['Access-Control-Allow-Origin']
  end

  test 'an ordinary response carries no access control headers while cors is off' do
    get :index

    assert_nil @response.headers['Access-Control-Allow-Origin']
    assert_nil @response.headers['Access-Control-Allow-Methods']
    assert_nil @response.headers['Access-Control-Max-Age']
  end

  test 'a preflight is answered with no body once cors is on' do
    with_cors
    process :index, method: 'OPTIONS'

    assert_response :success
    assert_predicate @response.body, :empty?

    assert_equal '*', @response.headers['Access-Control-Allow-Origin']
    assert_equal 'POST, GET, OPTIONS', @response.headers['Access-Control-Allow-Methods']
    assert_equal '1728000', @response.headers['Access-Control-Max-Age']
  end

  # That is how a bearer token arrives (RFC 6750 section 2.1).  Without it in the allowed
  # headers a browser refuses to send the one credential the API documents, which would leave
  # cross-origin calls working only for anonymous ones.
  test 'a preflight allows the Authorization header' do
    with_cors
    process :index, method: 'OPTIONS'

    assert_match 'Authorization', @response.headers['Access-Control-Allow-Headers']
  end

  # A preflight carries no credentials by design, so it must not reach :authenticate -- which
  # would turn it away.  Rendering in a before_action is what halts the chain.
  test 'a preflight is not authenticated and is not logged' do
    with_cors
    logout

    assert_no_difference 'Platform::ApplicationLog.count' do
      process :index, method: 'OPTIONS'
    end

    assert_response :success
    assert_nil Platform::Config.current_user
  end

  # The headers a browser actually checks: an approved preflight only buys the right to make the
  # request, not the right to read what comes back.
  test 'an ordinary response carries the access control headers once cors is on' do
    with_cors
    login_as user # so the call is answered rather than sent to login

    get :index

    assert_response :success
    assert_equal '*', @response.headers['Access-Control-Allow-Origin']
    assert_equal 'POST, GET, OPTIONS', @response.headers['Access-Control-Allow-Methods']
    assert_equal '1728000', @response.headers['Access-Control-Max-Age']
  end

private

  def with_cors
    cors = Platform::Config.api.merge(cors_enabled: true)
    Platform::Config.stubs(:api).returns(cors)
  end

end # class Platform::Api::BaseControllerTest
