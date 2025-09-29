class Platform::OauthControllerTest < Platform::ControllerTestCase

  test 'authorize requires client_id' do
    get :authorize
    assert_response :success
    assert_match 'client_id must be provided', @response.body
  end

  # Ticket 18822
  test 'authorize gracefully fails if no client app' do
    login_as user
    get :authorize, :params => {:client_id => 'invalid', :redirect_uri => 'http://foo.com/callback'}
    assert_response :redirect
    assert_redirected_to 'http://foo.com/callback?error=unauthorized_application&error_description=invalid+client+application+id'
  end

  test 'get authorize' do
    login_as user
    app.create_request_token(user, callback_url)

    get :authorize, :params => {:client_id => app.id}
    assert_response :success

    # from app/views/platform/oauth/authorize_web.html.erb
    assert_select 'div.platform-authorize-outer'
  end

  # Ticket 19135
  test 'grant_type password allowed' do
    user.update!(:name => 'foo', :password => 'bar')
    app.allow_grant_type_password!

    get :request_token, :params => {:grant_type => 'password', :client_id => app.key, :client_secret => app.secret, :username => 'foo', :password => 'bar'}
    assert_response :success

    assert_match 'access_token', @response.body
  end

  # Ticket 19193
  test 'grant_type password allowed iphone' do
    user.update!(:name => 'foo', :password => 'bar')
    app.allow_grant_type_password!

    @request.user_agent = 'iPhone'
    get :request_token, :params => {:grant_type => 'password', :client_id => app.key, :client_secret => app.secret, :username => 'foo', :password => 'bar'}
    assert_response :success

    expected = ['access_token', 'expires_in', 'refresh_token']
    assert_equal expected, JSON.parse(@response.body).keys.sort, 'iPhone clients should get json'
  end

  # Ticket 19135
  test 'grant_type password denied' do
    get :request_token, :params => {:grant_type => 'password', :client_id => app.key}
    assert_response :unauthorized
    assert_match 'not authorized', @response.body
  end

  # Ticket 19135
  test 'request_token with invalid client key' do
    get :request_token, :params => {:grant_type => 'password', :client_id => 'invalid'}
    assert_response :unauthorized
    assert_match 'invalid client application id', @response.body
  end

  # Ticket 19177
  test 'validate_token invalid token' do
    get :validate_token, :params => {:access_token => 'invalid'}
    assert_response :bad_request

    result = JSON.parse(@response.body)
    assert_equal 'invalid_token', result['error']
    assert_match 'invalid token', result['error_description']
  end

  # Ticket 19177
  test 'validate_token valid token' do
    access_token = Platform::Oauth::AccessToken.create!(:user => user, :application => app, :token => 'foo')
    get :validate_token, :params => {:access_token => access_token.token}
    assert_response :success

    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  # Ticket 16124
  test 'invalidate_token' do
    access_token = Platform::Oauth::AccessToken.create(:user => user, :application => app, :token => 'foo')
    get :invalidate_token, :params => {:access_token => access_token.token}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result'] # Ticket 19267
  end

private

  def callback_url
    'http://callback.url'
  end

end
