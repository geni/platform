require 'test_helper'

class Platform::OauthControllerTest < Platform::ControllerTestCase

  test 'authorize requires client_id' do
    get :authorize
    assert_response :success
    assert_match 'client_id must be provided', @response.body
  end

  # Ticket 18822
  test 'authorize gracefully fails if no client app' do
    login_as user
    get :authorize, params: {client_id: 'invalid', redirect_uri: 'http://foo.com/callback'}
    assert_response :redirect
    assert_redirected_to 'http://foo.com/callback?error=unauthorized_application&error_description=invalid+client+application+id'
  end

  test 'get authorize' do
    login_as user
    app.create_request_token(user, callback_url)

    get :authorize, params: {client_id: app.id}
    assert_response :success

    # from app/views/platform/oauth/authorize_web.html.erb
    assert_select 'div.platform-authorize-outer'
  end

  # Ticket 19135
  test 'grant_type password allowed' do
    user.update!(name: 'foo', password: 'bar')
    app.allow_grant_type_password!

    get :request_token, params: {grant_type: 'password', client_id: app.key, client_secret: app.secret, username: 'foo', password: 'bar'}
    assert_response :success

    assert_match 'access_token', @response.body
  end

  # Ticket 19193
  test 'grant_type password allowed iphone' do
    user.update!(name: 'foo', password: 'bar')
    app.allow_grant_type_password!

    @request.user_agent = 'iPhone'
    get :request_token, params: {grant_type: 'password', client_id: app.key, client_secret: app.secret, username: 'foo', password: 'bar'}
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
    get :request_token, params: {grant_type: 'password', client_id: app.key}
    assert_response :unauthorized
    assert_match 'not authorized', @response.body
  end

  # Ticket 19135
  test 'request_token with invalid client key' do
    get :request_token, params: {grant_type: 'password', client_id: 'invalid'}
    assert_response :unauthorized
    assert_match 'invalid client application id', @response.body
  end

  # Ticket 19177
  test 'validate_token invalid token' do
    get :validate_token, params: {access_token: 'invalid'}
    assert_response :bad_request

    result = JSON.parse(@response.body)
    assert_equal 'invalid_token', result['error']
    assert_match 'invalid token', result['error_description']
  end

  # Ticket 19177
  test 'validate_token valid token' do
    access_token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'foo')
    get :validate_token, params: {access_token: access_token.token}
    assert_response :success

    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  # Ticket 16124
  test 'invalidate_token' do
    access_token = Platform::Oauth::AccessToken.create(user: user, application: app, token: 'foo')
    get :invalidate_token, params: {access_token: access_token.token}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result'] # Ticket 19267
  end

  ##########################################################################
  #### authorize -- response_type=code
  ##########################################################################

  test 'authorize sends a guest to the login page and remembers the request' do
    get :authorize, params: {client_id: app.id, response_type: 'code', state: 'abc',
                             scope: 'user_basic'}
    assert_redirected_to Platform::Config.login_url(client_id: app.id.to_s, display: 'web')

    # Only the keys that mean something to #authorize are kept.  The whole params hash used to
    # go into the session, and the login controller hands that hash to redirect_to -- so :host,
    # :protocol and :only_path were a way to turn the post-login redirect off-site.
    stashed = session[:oauth_login_redirect_params]
    assert_equal '/platform/oauth', stashed['controller']
    assert_equal 'authorize',       stashed['action']
    assert_equal app.id.to_s,       stashed['client_id']
    assert_equal 'abc',             stashed['state']
    assert_equal 'user_basic',      stashed['scope']
  end

  test 'authorize does not stash a parameter that is not on the allowlist' do
    get :authorize, params: {client_id: app.id, host: 'evil.example.com', only_path: 'false',
                             protocol: 'http'}

    stashed = session[:oauth_login_redirect_params]
    %w[host only_path protocol].each do |key|
      assert_not stashed.key?(key), "#{key} should not be carried across login"
    end
  end

  test 'authorize requires a redirect_uri when the application has no callback_url' do
    login_as user
    no_callback = create_app(callback_url: nil)

    get :authorize, params: {client_id: no_callback.id}
    assert_response :success
    assert_match 'redirect_uri must be provided', @response.body
  end

  test 'authorize refuses a response_type it does not implement' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'id_token'}
    assert_response :redirect
    assert_match 'unsupported_response_type', @response.redirect_url
  end

  test 'authorize refuses a redirect_uri pointing at another host' do
    login_as user

    get :authorize, params: {client_id: app.id, redirect_uri: 'http://evil.example.com/callback'}
    assert_response :forbidden
    assert_match 'different server', @response.body
  end

  test 'authorize shows the consent form' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'code'}
    assert_response :success
    assert_select 'div.platform-authorize-outer'
  end

  # The form and the javascript that submits it both live in _authorize_form, and both of its
  # blocks were written `<% form_tag do %>` / `<% javascript_tag do %>` -- which discards what the
  # block captures.  So the consent page rendered, with no form in it and no handlers on the
  # buttons: consent could not be given through a browser on any display, and every path these
  # tests reach by POSTing authorize=1 directly was unreachable by a real user.
  test 'the consent form is rendered, with the request carried in hidden fields' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'code', state: 'abc',
                             scope: 'user_basic', redirect_uri: app.callback_url}
    assert_response :success

    assert_select 'form#auth_form' do
      assert_select 'input[name=response_type][value=?]', 'code'
      assert_select 'input[name=client_id][value=?]',     app.id.to_s
      assert_select 'input[name=redirect_url][value=?]',  app.callback_url
      assert_select 'input[name=state][value=?]',         'abc'
      # The scope the client asked for, which used to go out blank -- see #render_action.
      assert_select 'input[name=scope][value=?]',         'user_basic'
      assert_select 'input[name=display][value=?]',       'web'
      assert_select 'input[name=authorize][value=?]',     '1'
    end
  end

  # The challenge arrives on the GET and the code is only minted once Allow is clicked, so it has
  # to survive the consent POST -- which means being in the form.
  test 'the consent form defaults the scope when the request named none' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'code'}
    assert_select 'form#auth_form' do
      assert_select 'input[name=scope][value=?]', 'basic'
    end
  end

  test 'the consent form carries the pkce challenge across' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'code',
                             code_challenge: challenge_for('a-verifier'),
                             code_challenge_method: 'S256'}
    assert_response :success

    assert_select 'form#auth_form' do
      assert_select 'input[name=code_challenge][value=?]', challenge_for('a-verifier')
      assert_select 'input[name=code_challenge_method][value=?]', 'S256'
    end
  end

  test 'the consent buttons are wired to the form' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'code'}
    assert_response :success

    assert_match "getElementById('auth_form').submit()", @response.body
    assert_match "getElementById('auth-do-accept')",     @response.body
    assert_match "getElementById('auth-do-cancel')",     @response.body
  end

  # All six displays render _authorize_form, so all six were affected.
  test 'every display that asks for consent renders the form' do
    login_as user

    %w[web iframe mobile fluid].each do |display|
      get :authorize, params: {client_id: app.id, display: display}
      assert_select 'form#auth_form', 1, "display=#{display} should render the consent form"
    end
  end

  test 'authorize issues a code when consent is given' do
    login_as user

    assert_difference 'Platform::Oauth::RequestToken.count' do
      post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                                authenticity_token: form_authenticity_token}
    end

    assert_response :redirect
    code = Platform::Oauth::RequestToken.order('id desc').first
    assert_equal app, code.application
    assert_equal user, code.user
    assert_match "code=#{code.code}", @response.redirect_url
    assert_match 'expires_in=', @response.redirect_url
  end

  test 'authorize records the application user when consent is given' do
    login_as user

    assert_difference 'Platform::ApplicationUser.count' do
      post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                                authenticity_token: form_authenticity_token}
    end
  end

  test 'authorize answers unauthorized when consent is refused' do
    login_as user

    assert_no_difference 'Platform::Oauth::RequestToken.count' do
      post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '0',
                                authenticity_token: form_authenticity_token}
    end

    assert_match 'status=unauthorized', @response.redirect_url
    assert_match 'message=canceled',    @response.redirect_url
  end

  # A trusted application has already been granted consent once and for all, so the form is
  # skipped even on a GET.
  test 'authorize issues a code to a trusted application without asking' do
    login_as user
    app.set_permission(:trusted, true)
    app.save!

    assert_difference 'Platform::Oauth::RequestToken.count' do
      get :authorize, params: {client_id: app.id, response_type: 'code'}
    end

    assert_response :redirect
    assert_match 'code=', @response.redirect_url
  end

  test 'authorize preserves the state the client sent' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                              state: 'client-csrf-value',
                              authenticity_token: form_authenticity_token}
    assert_match 'state=client-csrf-value', @response.redirect_url
  end

  # A hidden iframe cannot show a consent form, so nobody can click Allow and the request can
  # only hang.  Answering through the xd channel lets the JSDK decide to open a popup.  This used
  # to render "authorize_hidden", a template that has never existed, and answer 500.
  test 'authorize in a hidden iframe says interaction is required rather than rendering a form' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'code', display: 'hidden',
                             origin: 'http://localhost'}
    assert_response :success
    assert_match 'interaction+required', @response.body
  end

  test 'authorize in a hidden iframe says the same for the token response type' do
    login_as user

    get :authorize, params: {client_id: app.id, response_type: 'token', display: 'hidden',
                             origin: 'http://localhost'}
    assert_response :success
    assert_match 'interaction+required', @response.body
  end

  ##########################################################################
  #### authorize -- response_type=token, the implicit grant
  ##########################################################################

  test 'authorize issues an access token for response_type token' do
    login_as user

    assert_difference 'Platform::Oauth::AccessToken.count' do
      post :authorize, params: {client_id: app.id, response_type: 'token', authorize: '1',
                                authenticity_token: form_authenticity_token}
    end

    assert_response :redirect
    assert_match 'access_token=', @response.redirect_url
    assert_match 'expires_in=',   @response.redirect_url
  end

  # The implicit grant must not hand out a refresh token over a redirect -- that is the whole
  # reason it has none.  The xd flow is the exception: it postMessages to a registered origin
  # rather than redirecting.
  test 'the implicit grant does not issue a refresh token over a redirect' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', authorize: '1',
                              authenticity_token: form_authenticity_token}
    assert_no_match 'refresh_token', @response.redirect_url
  end

  test 'the implicit grant issues a refresh token over the cross-domain channel' do
    login_as user

    assert_difference 'Platform::Oauth::RefreshToken.count' do
      post :authorize, params: {client_id: app.id, response_type: 'token', display: 'popup',
                                origin: 'http://localhost', authorize: '1',
                                authenticity_token: form_authenticity_token}
    end

    assert_response :success
    assert_match 'refresh_token', @response.body
  end

  ##########################################################################
  #### authorize -- the cross-domain channel
  ##########################################################################

  # The popup template posts to the registered origin rather than to "*".  While :xd_origin is
  # staged it still falls back to "*", byte for byte what the old template did.
  test 'an xd response goes to the registered origin when the opener claims one' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', display: 'popup',
                              origin: 'http://localhost', authorize: '1',
                              authenticity_token: form_authenticity_token}
    assert_response :success
    assert_match 'http://localhost', @response.body
  end

  test 'an xd response falls back to a wildcard origin while the check is staged' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', display: 'popup',
                              authorize: '1', authenticity_token: form_authenticity_token}
    assert_response :success
    assert_match '"*"', @response.body
  end

  # With the check enforced and nothing registered to post to, a credential is not delivered to
  # whatever opened the window.
  test 'an xd credential is refused when there is no registered origin to send it to' do
    login_as user
    no_origin = create_app(callback_url: nil, url: nil)
    Platform::Config.stubs(:oauth_enforce?).returns(false)
    Platform::Config.stubs(:oauth_enforce?).with(:xd_origin).returns(true)

    post :authorize, params: {client_id: no_origin.id, response_type: 'token', display: 'popup',
                              authorize: '1', authenticity_token: form_authenticity_token}
    assert_response :bad_request
    assert_match 'no registered origin', @response.body
  end

  # Only the response parameters go back to the opener.  The template used to serialize the whole
  # params hash, so anything an attacker put on the request came back out in a message the
  # receiving page dispatches on.
  test 'an xd payload carries only the response parameters' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', display: 'popup',
                              origin: 'http://localhost', authorize: '1',
                              injected: 'should-not-come-back',
                              authenticity_token: form_authenticity_token}
    assert_response :success
    assert_no_match 'should-not-come-back', @response.body
  end

  test 'an xd payload carries the state and callback the request sent' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', display: 'popup',
                              origin: 'http://localhost', authorize: '1',
                              state: 'abc', callback: 'cb7',
                              authenticity_token: form_authenticity_token}
    assert_match 'state=abc',    @response.body
    assert_match 'callback=cb7', @response.body
  end

  ##########################################################################
  #### display
  ####
  #### #display chooses the template, so an unknown value used to interpolate straight into a
  #### template name -- ?display=banana rendered "authorize_banana", which does not exist, and
  #### the endpoint answered 500 to anyone who asked.
  ##########################################################################

  test 'an unknown display falls back to the web form' do
    login_as user

    get :authorize, params: {client_id: app.id, display: 'banana'}
    assert_response :success
    assert_select 'div.platform-authorize-outer'
  end

  test 'each known display renders its own consent template' do
    login_as user

    %w[web iframe mobile fluid].each do |display|
      get :authorize, params: {client_id: app.id, display: display}
      assert_response :success, "display=#{display} should render"
    end
  end

  test 'a mobile user agent gets the mobile form whatever the display asks for' do
    login_as user
    @request.user_agent = 'iPhone'

    get :authorize, params: {client_id: app.id, display: 'web'}
    assert_response :success
    assert_equal 'mobile', @controller.send(:display)
  end

  # A desktop application has nowhere to redirect to, so it lands on this server's own
  # auth_success / auth_failed pages with the response in the fragment.
  test 'a desktop application lands on auth_success' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', display: 'desktop',
                              authorize: '1', authenticity_token: form_authenticity_token}
    assert_response :redirect
    assert_match 'auth_success', @response.redirect_url
    assert_match 'access_token=', @response.redirect_url
  end

  test 'a desktop application lands on auth_failed when consent is refused' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'token', display: 'desktop',
                              authorize: '0', authenticity_token: form_authenticity_token}
    assert_response :redirect
    assert_match 'auth_failed', @response.redirect_url
  end

  test 'auth_success renders without a layout' do
    get :auth_success
    assert_response :success
  end

  test 'auth_failed renders without a layout' do
    get :auth_failed
    assert_response :success
  end

  test 'xd renders without a layout' do
    get :xd
    assert_response :success
  end

  ##########################################################################
  #### request_token -- grant_type=authorization_code
  ##########################################################################

  test 'the authorization_code grant exchanges a code for tokens' do
    code = app.create_request_token(user, app.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal %w[access_token expires_in refresh_token scope], body.keys.sort
    assert_not_nil Platform::Oauth::AccessToken.find_by_presented_token(body['access_token'])
    assert_not_nil Platform::Oauth::RefreshToken.find_by_presented_token(body['refresh_token'])
  end

  # A code is single use: it is destroyed as it is redeemed, so replaying it gets nothing.
  test 'the authorization_code grant consumes the code' do
    code = app.create_request_token(user, app.callback_url)

    assert_difference 'Platform::Oauth::RequestToken.count', -1 do
      post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                    client_secret: app.secret, code: code.code,
                                    redirect_uri: app.callback_url}
    end

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :bad_request
    assert_match 'Invalid authorization code', @response.body
  end

  test 'the authorization_code grant requires a code' do
    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret}
    assert_response :bad_request
    assert_match 'Code must be provided', @response.body
  end

  # RFC 6749 section 5.2 has one invalid_request for a code that is unknown, expired, revoked or
  # another application's, because saying which would say whether the code ever existed.
  test 'the authorization_code grant will not redeem another application\'s code' do
    other = create_app(name: 'Other')
    code = other.create_request_token(user, other.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :bad_request
    assert_match 'Invalid authorization code', @response.body
  end

  test 'the authorization_code grant refuses an expired code' do
    code = app.create_request_token(user, app.callback_url)
    code.update!(valid_to: 1.minute.ago)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :bad_request
    assert_match 'Invalid authorization code', @response.body
  end

  test 'the authorization_code grant requires the redirect_uri to match the one the code was issued for' do
    code = app.create_request_token(user, 'http://localhost/one')

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: 'http://localhost/two'}
    assert_response :bad_request
    assert_match 'Redirection url must match', @response.body
  end

  ##########################################################################
  #### Client authentication on the token endpoint (RFC 6749 section 2.3)
  ##########################################################################

  # The grant used to match the code against the application id and nothing else, so anyone who
  # got hold of a code could redeem it with only the public client_id.
  test 'the authorization_code grant rejects a wrong client_secret once the check is on' do
    enforce :client_secret
    code = app.create_request_token(user, app.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: 'wrong', code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :unauthorized
    assert_match 'invalid_client', @response.body
    assert_equal 'Basic realm="oauth"', @response.headers['WWW-Authenticate']
  end

  test 'the authorization_code grant rejects a missing client_secret once the check is on' do
    enforce :client_secret
    code = app.create_request_token(user, app.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  code: code.code, redirect_uri: app.callback_url}
    assert_response :unauthorized
    assert_match 'Client authentication failed', @response.body
  end

  # While the check is staged a client that sends no secret still works, which is the point of
  # staging it.
  test 'the authorization_code grant still accepts a missing client_secret while the check is staged' do
    code = app.create_request_token(user, app.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  code: code.code, redirect_uri: app.callback_url}
    assert_response :success
  end

  # RFC 6749 section 2.3.1 makes HTTP Basic the preferred way to present client credentials, and a
  # client using it should not have to repeat the id in the query string.
  test 'client credentials may arrive in an HTTP Basic header' do
    enforce :client_secret
    code = app.create_request_token(user, app.callback_url)
    @request.headers['Authorization'] = basic_header(app.key, app.secret)

    post :request_token, params: {grant_type: 'authorization_code', code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :success
  end

  test 'a wrong secret in an HTTP Basic header is rejected' do
    enforce :client_secret
    code = app.create_request_token(user, app.callback_url)
    @request.headers['Authorization'] = basic_header(app.key, 'wrong')

    post :request_token, params: {grant_type: 'authorization_code', code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :unauthorized
  end

  # A public client cannot keep a secret -- its "secret" ships inside something the user can read
  # -- so it is exempt, and brings PKCE instead.
  test 'a public client is exempt from the client_secret' do
    enforce :client_secret
    app.set_permission(:public_client, true)
    app.save!
    code = app.create_request_token(user, app.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  code: code.code, redirect_uri: app.callback_url}
    assert_response :success
  end

  ##########################################################################
  #### PKCE (RFC 7636)
  ##########################################################################

  test 'authorize binds a code_challenge to the code it issues' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                              code_challenge: challenge_for('a-verifier'),
                              code_challenge_method: 'S256',
                              authenticity_token: form_authenticity_token}

    code = Platform::Oauth::RequestToken.order('id desc').first
    assert_equal challenge_for('a-verifier'), code.code_challenge
    assert_equal 'S256', code.code_challenge_method
  end

  # Only S256.  RFC 7636 also defines "plain", which offers no protection against an attacker who
  # can read the authorization request, and nothing here uses PKCE yet -- so there is no legacy
  # client to accommodate.
  test 'authorize ignores a code_challenge_method it does not accept' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                              code_challenge: challenge_for('a-verifier'),
                              code_challenge_method: 'plain',
                              authenticity_token: form_authenticity_token}

    assert_nil Platform::Oauth::RequestToken.order('id desc').first.code_challenge
  end

  test 'the authorization_code grant accepts a matching code_verifier' do
    code = app.create_request_token(user, app.callback_url, 'basic', 600,
                                    {code_challenge: challenge_for('a-verifier'),
                                     code_challenge_method: 'S256'})

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url, code_verifier: 'a-verifier'}
    assert_response :success
  end

  # Always rejected, switch or no switch: the only way to get here is to present a verifier that
  # does not match a challenge the same client chose moments earlier.
  test 'the authorization_code grant rejects a code_verifier that does not match' do
    code = app.create_request_token(user, app.callback_url, 'basic', 600,
                                    {code_challenge: challenge_for('a-verifier'),
                                     code_challenge_method: 'S256'})

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url, code_verifier: 'another-verifier'}
    assert_response :bad_request
    assert_match 'code_verifier did not match', @response.body
  end

  test 'a code issued with a challenge requires a verifier once the check is on' do
    enforce :pkce
    code = app.create_request_token(user, app.callback_url, 'basic', 600,
                                    {code_challenge: challenge_for('a-verifier'),
                                     code_challenge_method: 'S256'})

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  client_secret: app.secret, code: code.code,
                                  redirect_uri: app.callback_url}
    assert_response :bad_request
    assert_match 'code_verifier must be provided', @response.body
  end

  test 'a public client must bring PKCE once the check is on' do
    enforce :pkce
    app.set_permission(:public_client, true)
    app.save!
    code = app.create_request_token(user, app.callback_url)

    post :request_token, params: {grant_type: 'authorization_code', client_id: app.key,
                                  code: code.code, redirect_uri: app.callback_url}
    assert_response :bad_request
    assert_match 'code_challenge is required', @response.body
  end

  ##########################################################################
  #### request_token -- grant_type=refresh_token
  ##########################################################################

  test 'the refresh_token grant exchanges a refresh token for a new pair' do
    refresh = app.create_refresh_token(user)

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: refresh.client_token}
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal %w[access_token expires_in refresh_token scope], body.keys.sort
    assert_not_equal refresh.client_token, body['refresh_token'], 'refresh tokens rotate'
  end

  test 'the refresh_token grant requires a refresh token' do
    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret}
    assert_response :bad_request
    assert_match 'Refresh token must be provided', @response.body
  end

  test 'the refresh_token grant will not redeem another application\'s token' do
    other = create_app(name: 'Other')
    refresh = other.create_refresh_token(user)

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: refresh.client_token}
    assert_response :bad_request
    assert_match 'Invalid refresh token', @response.body
  end

  test 'the refresh_token grant refuses an expired token' do
    refresh = app.create_refresh_token(user)
    refresh.update!(valid_to: 1.minute.ago)

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: refresh.client_token}
    assert_response :bad_request
    assert_match 'Refresh token expired', @response.body
  end

  # Refresh tokens rotate, so a token presented twice has two holders and there is no way to tell
  # which one is the real client: the whole family goes.
  # Outside the grace period.  A second presentation is only evidence of two holders once it can no
  # longer be explained as a retry -- see the grace period tests below.
  test 'replaying a refresh token revokes every token the application holds' do
    refresh = app.create_refresh_token(user)
    access  = app.find_or_create_access_token(user)
    presented = refresh.client_token

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: presented}
    assert_response :success

    age_out_the_exchange(refresh)

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: presented}
    assert_response :bad_request
    assert_match 'already been used', @response.body
    assert_match 'invalid_grant',     @response.body

    assert_not_nil access.reload.invalidated_at, 'the access token should have been revoked too'
  end

  # Inside the window the same second presentation is a retry and is served, because a client that
  # never received our reply holds only the token it started with.  RFC 9700 section 4.14.2 asks for
  # family revocation on replay and leaves the window to the implementation; Okta's refresh token
  # rotation ships the same allowance.  Registry/Platform::Config
  # oauth_refresh_token_grace_period is the window, and 0 restores strict detection.
  test 'a second refresh inside the grace period is served, not revoked' do
    refresh   = app.create_refresh_token(user)
    presented = refresh.client_token

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: presented}
    assert_response :success
    first = JSON.parse(@response.body)

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: presented}
    assert_response :success
    second = JSON.parse(@response.body)

    assert_nil second['error'], 'a retry inside the window should not be refused'
    assert second['refresh_token'].present?, 'the retry should get a usable refresh token'

    # Not the same value: refresh tokens are digested at rest, so what the first caller was handed
    # is not recoverable and cannot be replayed.  The retry gets its own.
    assert_not_equal first['refresh_token'], second['refresh_token']

    # Presentable, and the first caller's is still live rather than swept up by the retry.
    assert_not_nil Platform::Oauth::RefreshToken.find_by_presented_token(second['refresh_token'])

    survivor = Platform::Oauth::RefreshToken.find_by_presented_token(first['refresh_token'])
    assert_not_nil survivor
    assert survivor.valid_token?, "the first caller's token should not have been revoked"
  end

  test 'the grace period does not revive a refresh token whose grant was withdrawn' do
    refresh   = app.create_refresh_token(user)
    presented = refresh.client_token

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: presented}
    assert_response :success
    first = JSON.parse(@response.body)

    # As a deauthorize or an admin revoke would: the replacement goes, and its liveness is what the
    # window reads to decide whether the grant still stands.
    Platform::Oauth::RefreshToken.find_by_presented_token(first['refresh_token']).invalidate!

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: app.secret, refresh_token: presented}
    assert_response :bad_request
    assert_match 'invalid_grant', @response.body, 'a withdrawn grant should not get sixty seconds of grace'
  end

  test 'the refresh_token grant rejects a wrong client_secret once the check is on' do
    enforce :client_secret
    refresh = app.create_refresh_token(user)

    post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                  client_secret: 'wrong', refresh_token: refresh.client_token}
    assert_response :unauthorized
    assert_match 'invalid_client', @response.body
  end

  # A client_credentials refresh token has no user behind it, so refreshing it answers another
  # client token rather than a user token.
  test 'refreshing a client token answers another client token' do
    refresh = app.create_refresh_token(nil)

    assert_difference 'Platform::Oauth::ClientToken.count' do
      post :request_token, params: {grant_type: 'refresh_token', client_id: app.key,
                                    client_secret: app.secret, refresh_token: refresh.client_token}
    end

    assert_response :success
  end

  ##########################################################################
  #### request_token -- grant_type=client_credentials
  ##########################################################################

  test 'the client_credentials grant issues a client token' do
    assert_difference 'Platform::Oauth::ClientToken.count' do
      post :request_token, params: {grant_type: 'client_credentials', client_id: app.key,
                                    client_secret: app.secret}
    end

    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal %w[access_token expires_in refresh_token scope], body.keys.sort
  end

  test 'the client_credentials grant requires the secret' do
    post :request_token, params: {grant_type: 'client_credentials', client_id: app.key}
    assert_response :bad_request
    assert_match 'Application secret must be provided', @response.body
  end

  # This grant has always required the secret, so there is no staged check in front of it -- a
  # wrong secret is rejected whatever the switches say.
  test 'the client_credentials grant rejects a wrong secret with no switch needed' do
    post :request_token, params: {grant_type: 'client_credentials', client_id: app.key,
                                  client_secret: 'wrong'}
    assert_response :bad_request
    assert_match 'Invalid application secret', @response.body
  end

  ##########################################################################
  #### request_token -- the rest
  ##########################################################################

  test 'request_token requires a client_id' do
    post :request_token, params: {grant_type: 'authorization_code'}
    assert_response :bad_request
    assert_match 'client_id must be provided', @response.body
  end

  test 'request_token refuses a grant_type it does not implement' do
    post :request_token, params: {grant_type: 'implicit', client_id: app.key}
    assert_response :bad_request
    assert_match 'unsupported_grant_type', @response.body
  end

  # The device grant is the one grant_type whose name is not a legal method suffix, so it is the
  # one that cannot be dispatched by interpolation.  RFC 8628 section 3.4 defines this spelling
  # and no other, so a conformant client sends exactly this -- and nothing else here would notice
  # if the endpoint only answered a bare 'device_code', which is a name the RFC never mentions.
  test 'request_token dispatches the RFC 8628 device grant URN' do
    code = app.create_device_code

    post :request_token, params: {grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
                                  client_id: app.key, device_code: code.device_code}

    # authorization_pending, not unsupported_grant_type: the handler ran and found the code
    # unapproved, which is the whole point -- the request reached oauth2_request_token_device_code.
    assert_match 'authorization_pending', @response.body
    assert_no_match(/unsupported_grant_type/, @response.body)
  end

  test 'request_token refuses the bare device_code spelling the RFC does not define' do
    post :request_token, params: {grant_type: 'device_code', client_id: app.key}
    assert_response :bad_request
    assert_match 'unsupported_grant_type', @response.body
  end

  test 'the unsupported_grant_type error names the grants that are actually wired up' do
    post :request_token, params: {grant_type: 'telepathy', client_id: app.key}

    Platform::OauthController::GRANT_HANDLERS.each_key do |grant|
      assert_match grant, @response.body, "the error should name #{grant}"
    end
  end

  test 'request_token defaults to the authorization_code grant' do
    post :request_token, params: {client_id: app.key, client_secret: app.secret}
    assert_response :bad_request
    assert_match 'Code must be provided', @response.body
  end

  # The password grant is a credential-testing oracle without client authentication: anyone
  # knowing the public client_id could post username/password pairs here, against this endpoint's
  # rate limits rather than the login form's lockout, MFA and captcha.
  test 'the password grant requires the client_secret once its own check is on' do
    enforce :client_secret_password
    user.update!(name: 'foo', password: 'bar')
    app.allow_grant_type_password!

    post :request_token, params: {grant_type: 'password', client_id: app.key, username: 'foo',
                                  password: 'bar'}
    assert_response :unauthorized
    assert_match 'Client authentication failed', @response.body
  end

  test 'the password grant requires a username' do
    app.allow_grant_type_password!

    post :request_token, params: {grant_type: 'password', client_id: app.key,
                                  client_secret: app.secret, password: 'bar'}
    assert_response :bad_request
    assert_match 'Username must be provided', @response.body
  end

  test 'the password grant requires a password' do
    app.allow_grant_type_password!

    post :request_token, params: {grant_type: 'password', client_id: app.key,
                                  client_secret: app.secret, username: 'foo'}
    assert_response :bad_request
    assert_match 'Password must be provided', @response.body
  end

  test 'the password grant refuses a username and password that do not match' do
    app.allow_grant_type_password!

    post :request_token, params: {grant_type: 'password', client_id: app.key,
                                  client_secret: app.secret, username: 'foo', password: 'wrong'}
    assert_response :bad_request
    assert_match 'Invalid username and/or password', @response.body
  end

  ##########################################################################
  #### validate_token / invalidate_token / revoke
  ####
  #### Both endpoints took a bare token and no credentials, which made validate_token a free
  #### token-validity oracle and invalidate_token a way for anyone holding a token to kill it.
  #### RFC 7009 section 2.1 requires the client to authenticate.
  ##########################################################################

  test 'validate_token is scoped to the authenticated client\'s own tokens' do
    other = create_app(name: 'Other')
    token = Platform::Oauth::AccessToken.create!(user: user, application: other, token: 'theirs')

    get :validate_token, params: {access_token: token.token, client_id: app.key,
                                  client_secret: app.secret}
    assert_response :bad_request
    assert_equal 'invalid_token', JSON.parse(@response.body)['error']
  end

  test 'validate_token accepts the client\'s own token' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    get :validate_token, params: {access_token: token.token, client_id: app.key,
                                  client_secret: app.secret}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  test 'validate_token refuses a client_id that names nothing' do
    get :validate_token, params: {access_token: 'anything', client_id: 'no-such-application'}
    assert_response :unauthorized
    assert_match 'invalid client application id', @response.body
  end

  test 'validate_token rejects an invalidated token' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'revoked')
    token.invalidate!

    get :validate_token, params: {access_token: token.token, client_id: app.key,
                                  client_secret: app.secret}
    assert_response :bad_request
    assert_equal 'invalid_token', JSON.parse(@response.body)['error']
  end

  test 'invalidate_token revokes the client\'s own token' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    post :invalidate_token, params: {access_token: token.token, client_id: app.key,
                                     client_secret: app.secret,
                                     authenticity_token: form_authenticity_token}
    assert_response :success
    assert_not_nil token.reload.invalidated_at
  end

  test 'invalidate_token will not revoke another application\'s token' do
    other = create_app(name: 'Other')
    token = Platform::Oauth::AccessToken.create!(user: user, application: other, token: 'theirs')

    post :invalidate_token, params: {access_token: token.token, client_id: app.key,
                                     client_secret: app.secret,
                                     authenticity_token: form_authenticity_token}
    # "OK" either way, per RFC 7009 section 2.2: saying the token was not found is the oracle this
    # closed.
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
    assert_nil token.reload.invalidated_at
  end

  test 'invalidate_token answers OK for a token that does not exist' do
    post :invalidate_token, params: {access_token: 'no-such-token', client_id: app.key,
                                     client_secret: app.secret,
                                     authenticity_token: form_authenticity_token}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  # RFC 7009 names the endpoint "revoke", and /oauth/revoke had been routed to a #revoke that
  # never existed.
  test 'revoke is invalidate_token' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    post :revoke, params: {access_token: token.token, client_id: app.key,
                           client_secret: app.secret, authenticity_token: form_authenticity_token}
    assert_response :success
    assert_not_nil token.reload.invalidated_at
  end

  # A GET on a revocation endpoint puts the token in the URL -- access logs, Referer headers --
  # and makes revocation reachable by anything that can cause a navigation.
  test 'revocation over GET is refused once the check is on' do
    enforce :revocation_auth
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    get :invalidate_token, params: {access_token: token.token, client_id: app.key,
                                    client_secret: app.secret}
    assert_response :unauthorized
    assert_match 'requires an authenticated client over POST', @response.body
    assert_nil token.reload.invalidated_at
  end

  test 'revocation without a client_id is refused once the check is on' do
    enforce :revocation_auth
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    post :invalidate_token, params: {access_token: token.token,
                                     authenticity_token: form_authenticity_token}
    assert_response :unauthorized
    assert_match 'requires an authenticated client over POST', @response.body
    assert_nil token.reload.invalidated_at
  end

  test 'revocation with a wrong secret is refused once the check is on' do
    enforce :revocation_auth
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    post :invalidate_token, params: {access_token: token.token, client_id: app.key,
                                     client_secret: 'wrong',
                                     authenticity_token: form_authenticity_token}
    assert_response :unauthorized
    assert_nil token.reload.invalidated_at
  end

  # While the check is staged a caller that sends no credentials gets the old behaviour,
  # including the unscoped token lookup -- which is the whole point of staging it.
  test 'revocation with no client_id keeps the old unscoped behaviour while the check is staged' do
    other = create_app(name: 'Other')
    token = Platform::Oauth::AccessToken.create!(user: user, application: other, token: 'theirs')

    get :invalidate_token, params: {access_token: token.token}
    assert_response :success
    assert_not_nil token.reload.invalidated_at
  end

  test 'validate_token accepts the token under its RFC 7009 name' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'mine')

    get :validate_token, params: {token: token.token, client_id: app.key,
                                  client_secret: app.secret}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  ##########################################################################
  #### deauthorize / logout
  ##########################################################################

  test 'deauthorize drops the viewer\'s authorization' do
    login_as user
    Platform::ApplicationUser.touch(app, user)

    get :deauthorize, params: {client_id: app.id}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  test 'deauthorize answers OK for a guest without touching anything' do
    get :deauthorize, params: {client_id: app.id}
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  test 'logout runs the host application\'s logout method' do
    login_as user

    get :logout
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
    assert_nil session[:user_id]
  end

  # The logout method is configuration rather than request input, so this was never reachable from
  # outside -- but it is #send rather than eval now, and a name that is not a method says so
  # rather than running whatever the string happens to contain.
  test 'logout reports a logout method that does not exist' do
    Platform::Config.stubs(:logout_method).returns('no_such_method')
    login_as user

    error = assert_raises(RuntimeError) { get :logout }
    assert_match 'Failed to execute no_such_method', error.message
  end

  test 'logout does nothing when the host application has no user integration' do
    Platform::Config.stubs(:site_user_info_enabled?).returns(false)
    login_as user

    get :logout
    assert_response :success
    assert_equal 'OK', JSON.parse(@response.body)['result']
  end

  ##########################################################################
  #### status -- the JSDK's "is this viewer signed in and authorized?" check
  ##########################################################################

  # #status answers the opener through the cross-domain channel, so every request here carries an
  # xd display -- a response posted back to the opener rather than redirected.
  test 'status requires an origin' do
    get :status, params: {client_id: app.id, display: 'popup'}
    assert_response :success
    assert_match 'origin+must+be+specified', @response.body
  end

  # No client_id means no registered origin to post to either, so the answer goes out to "*".
  # That is deliberate: #status answers callers it cannot identify, and those answers carry
  # nothing worth protecting.
  test 'status requires a client it can identify' do
    get :status, params: {origin: 'http://localhost', display: 'popup'}
    assert_response :success
    assert_match 'client_id+must+be+specified', @response.body
    assert_match '"*"', @response.body
  end

  # The check compared only the host against site_domain, so an http origin passed a check meant
  # to establish that the caller is the registered application.
  test 'status refuses an origin the application has not registered' do
    get :status, params: {client_id: app.id, origin: 'http://evil.example.com', display: 'popup'}
    assert_response :success
    assert_match 'invalid+origin', @response.body
  end

  test 'status answers unknown for a guest' do
    get :status, params: {client_id: app.id, origin: 'http://localhost', display: 'popup'}
    assert_response :success
    assert_match 'status=unknown', @response.body
  end

  test 'status answers unauthorized for a user who has not authorized the application' do
    login_as user

    get :status, params: {client_id: app.id, origin: 'http://localhost', display: 'popup'}
    assert_response :success
    assert_match 'status=unauthorized', @response.body
  end

  test 'status answers authorized for a user who has' do
    login_as user
    Platform::ApplicationUser.touch(app, user)

    get :status, params: {client_id: app.id, origin: 'http://localhost', display: 'popup'}
    assert_response :success
    assert_match 'status=authorized', @response.body
  end

  ##########################################################################
  #### Scope
  ##########################################################################

  # #granted_scope needs something to narrow against, and nothing is registered for any
  # application while enable_scopes? is off -- so the request passes through, which is the
  # existing behaviour.
  test 'the requested scope is granted while the scope system is off' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                              scope: 'user_basic,family_basic',
                              authenticity_token: form_authenticity_token}

    assert_equal 'user_basic,family_basic',
                 Platform::Oauth::RequestToken.order('id desc').first.scope
  end

  test 'the scope defaults to basic' do
    login_as user

    post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                              authenticity_token: form_authenticity_token}

    assert_equal 'basic', Platform::Oauth::RequestToken.order('id desc').first.scope
  end

  # The response used to echo the requested scope over the granted one, so a client could not tell
  # when its request had been narrowed -- and the response looked like confirmation of it.
  test 'the response reports the scope that was granted, not the one that was asked for' do
    login_as user
    Platform::Scope.find_or_create('user_basic')
    app.add_scope('user_basic')
    Platform::Config.stubs(:enable_scopes?).returns(true)

    post :authorize, params: {client_id: app.id, response_type: 'code', authorize: '1',
                              scope: 'user_basic,family_basic',
                              authenticity_token: form_authenticity_token}

    assert_match 'scope=user_basic', @response.redirect_url
    assert_no_match(/family_basic/, @response.redirect_url)
  end

private

  def callback_url
    'http://callback.url'
  end

  # Turn one hardening check on and leave the rest staged.  They all ship off -- see
  # Platform::Config.oauth_enforce? -- so this is how the enforcing branch gets exercised.
  def enforce(check)
    Platform::Config.stubs(:oauth_enforce?).returns(false)
    Platform::Config.stubs(:oauth_enforce?).with(check).returns(true)
  end

  # RFC 6749 section 2.3.1: the components are form-urlencoded before being base64'd.
  def basic_header(id, secret)
    "Basic #{Base64.encode64("#{CGI.escape(id)}:#{CGI.escape(secret)}")}"
  end

  def challenge_for(verifier)
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier)).delete('=')
  end


  # Pushes an exchange back past the grace period, so that presenting the token again is a replay
  # rather than a retry.  Written as an UPDATE because exchanged_at is set by the exchange's own
  # statement, and assigning it on a stale object would write that object's other columns back too.
  def age_out_the_exchange(token)
    klass = token.class
    stale = klass.connection.quoted_date(
              klass.now_in_database_timezone - Platform::Config.oauth_refresh_token_grace_period - 60)

    klass.connection.update("UPDATE #{klass.table_name} SET exchanged_at = '#{stale}' WHERE id = #{token.id.to_i}")
    token.reload
  end

end
