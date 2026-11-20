require_relative '../../../test_helper'

class Platform::OauthControllerTest < ActionController::TestCase

  setup do
    @routes = Platform::Engine.routes
  end

  test 'authorize requires login' do
    get :authorize
    assert_template 'authorize_failure'
  end

  # Ticket 18822
  test 'authorize gracefully fails if no client app' do
    login_as user
    get :authorize, :client_id => 'invalid', :redirect_uri => 'http://foo.com/callback'
    assert_response :redirect
    assert_match 'invalid', @response.body
  end

  test 'get authorize' do
    login_as user
    token = app.create_request_token(user, callback_url)

    get :authorize, :client_id => app.id
    assert_response :success
    assert_template 'authorize_web'
  end


  ##########################################################################
  #### The refresh_token grant and its grace period
  ####
  #### RFC 9700 section 4.14.2 asks for family revocation on replay and leaves the detection
  #### window to the implementation; Okta's refresh token rotation ships that allowance as its
  #### grace period.
  ##########################################################################

  # The response has to carry a refresh token a client can actually present again.  This is the
  # assertion that catches handing back a digested token's unrecoverable value: refresh tokens are
  # in oauth_hashed_token_types, so OauthToken#client_token answers nil for any row read back from
  # the database, and a reply built from one would serialize "refresh_token": null.
  test 'the refresh grant returns a usable refresh token' do
    refresh = app.create_refresh_token(user)

    get :request_token, :grant_type => 'refresh_token', :refresh_token => refresh.client_token,
                        :client_id => app.key, :client_secret => app.secret
    assert_response :success

    result = JSON.parse(@response.body)

    assert result['refresh_token'].present?, "no refresh token in #{@response.body}"
    assert result['access_token'].present?,  "no access token in #{@response.body}"

    # Presentable: the value in the reply finds the row it names, and that row is usable.
    issued = Platform::Oauth::RefreshToken.find_by_presented_token(result['refresh_token'])
    assert_not_nil issued, 'the returned value should find its row'
    assert issued.valid_token?
  end

  # Two presentations of one token inside the window: the second is a retry, and it is served
  # rather than answered by revoking everything the user has.
  test 'a second refresh inside the grace period is served, not revoked' do
    refresh   = app.create_refresh_token(user)
    presented = refresh.client_token

    get :request_token, :grant_type => 'refresh_token', :refresh_token => presented,
                        :client_id => app.key, :client_secret => app.secret
    assert_response :success
    first = JSON.parse(@response.body)

    get :request_token, :grant_type => 'refresh_token', :refresh_token => presented,
                        :client_id => app.key, :client_secret => app.secret
    assert_response :success
    second = JSON.parse(@response.body)

    assert second['refresh_token'].present?, "no refresh token in #{@response.body}"
    assert_not_equal first['refresh_token'], second['refresh_token'],
                     'the value cannot be replayed, so the retry gets its own'

    # And the first caller's token is still good: it was not swept up by a revocation.
    # #find_by_presented_token is a lookup rather than a validity check -- it answers invalidated
    # rows too -- so the liveness is what gets asserted.
    first_issued = Platform::Oauth::RefreshToken.find_by_presented_token(first['refresh_token'])
    assert_not_nil first_issued
    assert first_issued.valid_token?, 'the first caller should not have been revoked by the retry'
  end

  # Outside the window the strict behaviour stands: two holders, and the family goes.
  test 'a second refresh outside the grace period revokes the family' do
    refresh   = app.create_refresh_token(user)
    presented = refresh.client_token

    get :request_token, :grant_type => 'refresh_token', :refresh_token => presented,
                        :client_id => app.key, :client_secret => app.secret
    assert_response :success
    first = JSON.parse(@response.body)

    # Push the exchange out of the window rather than waiting for it.
    exchanged = Platform::Oauth::RefreshToken.find(refresh.id)
    stale     = exchanged.class.connection.quoted_date(
                  Platform::Oauth::RefreshToken.now_in_database_timezone -
                    Platform::Config.oauth_refresh_token_grace_period - 60)
    exchanged.class.connection.update(
      "UPDATE #{exchanged.class.table_name} SET exchanged_at = '#{stale}' WHERE id = #{exchanged.id.to_i}"
    )

    get :request_token, :grant_type => 'refresh_token', :refresh_token => presented,
                        :client_id => app.key, :client_secret => app.secret

    result = JSON.parse(@response.body)
    assert_equal 'invalid_grant', result['error']
    assert_match 'revoked',       result['error_description']

    # The family is gone, including the replacement the first caller is holding.  The row survives
    # the sweep -- #revoke_all_for invalidates rather than deletes -- so this asserts that it can no
    # longer be used, not that it has vanished.
    first_issued = Platform::Oauth::RefreshToken.find_by_presented_token(first['refresh_token'])
    assert_not_nil first_issued
    assert first_issued.invalidated?, 'the family revocation should have swept this up'
    assert !first_issued.valid_token?
  end

  # Ticket 19135
  test 'grant_type password allowed' do
    user.update_attributes!(:name => 'foo', :password => 'bar')
    app.allow_grant_type_password!

    get :request_token, :grant_type => 'password', :client_id => app.key, :client_secret => app.secret, :username => 'foo', :password => 'bar'
    assert_response :success

    assert_match 'access_token', @response.body
  end

  # Ticket 19193
  test 'grant_type password allowed iphone' do
    user.update_attributes!(:name => 'foo', :password => 'bar')
    app.allow_grant_type_password!

    @request.user_agent = 'iPhone'
    get :request_token, :grant_type => 'password', :client_id => app.key, :client_secret => app.secret, :username => 'foo', :password => 'bar'
    assert_response :success

    # scope joined this list when the grant started reporting what it actually granted rather
    # than echoing what was asked for.  RFC 6749 section 5.1 makes scope REQUIRED in the response
    # when the granted scope differs from the requested one, and now that #granted_scope can
    # narrow, this is the only way a client can tell that it was narrowed.
    expected = ['access_token', 'expires_in', 'refresh_token', 'scope']
    assert_equal expected, JSON.parse(@response.body).keys.sort, 'iPhone clients should get json'
  end

  # Ticket 19135
  test 'grant_type password denied' do
    get :request_token, :grant_type => 'password', :client_id => app.key
    assert_response :unauthorized
    assert_match 'not authorized', @response.body
  end

  # Ticket 19135
  test 'request_token with invalid client key' do
    get :request_token, :grant_type => 'password', :client_id => 'invalid'
    assert_response :unauthorized
    assert_match 'invalid client application id', @response.body
  end

  # Ticket 19177
  test 'validate_token invalid token' do
    get :validate_token, :access_token => 'invalid'
    assert_response :bad_request

    result = JSON.parse(@response.body)
    assert_equal 'invalid_token', result['error']
    assert_match 'invalid token', result['error_description']
  end

  # Ticket 19177
  test 'validate_token valid token' do
    access_token = Platform::Oauth::AccessToken.create!(:user => user, :application => app, :token => "foo_#{Time.now.to_f}")
    get :validate_token, :access_token => access_token.token
    assert_response :success

    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  # Ticket 16124
  test 'invalidate_token' do
    access_token = Platform::Oauth::AccessToken.create(:user => user, :application => app, :token => "foo_#{Time.now.to_f}")
    get :invalidate_token, :access_token => access_token.token
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result'] # Ticket 19267
  end

private

  def callback_url
    'http://callback.url'
  end

end
