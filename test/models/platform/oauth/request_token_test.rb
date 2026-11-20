require 'test_helper'

module Platform::Oauth
  class RequestTokenTest < Platform::TestCase

    test 'authorize with user' do
      token = RequestToken.create(application: app, user: user, token: 'foo')
      token.authorize!
      assert_equal @user, token.reload.user
    end

    test 'a user is required' do
      ex = assert_raise ActiveRecord::RecordInvalid do
        RequestToken.create!(application: app, token: 'foo')
      end
      assert_match(/user.*blank/i, ex.message)
    end

    ##########################################################################
    #### code
    ####
    #### #code, not #token: request tokens are stored as a digest, so #token is the digest and
    #### only #code can actually be redeemed.  Handing back #token would give the client a string
    #### that looks like an authorization code and can never be exchanged.
    ##########################################################################

    test 'code is the redeemable authorization code, not the stored digest' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')

      assert_not_nil token.code
      assert_not_equal token.token, token.code
      assert_equal Platform::Helper.token_digest(token.code), token.token
    end

    test 'the code redeems against the stored digest' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')

      assert_equal token.id, RequestToken.find_by_presented_token(token.code).id
    end

    test 'code is nil on a record loaded back from the database' do
      code  = app.create_request_token(user, 'http://localhost/cb', 'basic').code
      found = RequestToken.find_by_token(Platform::Helper.token_digest(code))

      assert_nil found.code, 'a digest cannot be turned back into the code that produced it'
    end

    test 'redirect_url reads the callback url the authorize request named' do
      token = app.create_request_token(user, 'http://localhost/cb?profile_id=7', 'basic')

      assert_equal 'http://localhost/cb?profile_id=7', token.redirect_url
      assert_equal token.callback_url, token.redirect_url
    end

    ##########################################################################
    #### create_request_token
    ##########################################################################

    test 'create_request_token records the user, callback and scope' do
      token = app.create_request_token(user, 'http://localhost/cb', 'user_email')

      assert_equal app.id,  token.application_id
      assert_equal user.id, token.user_id
      assert_equal 'http://localhost/cb', token.callback_url
      assert_equal 'user_email', token.scope
    end

    test 'the scope defaults to basic' do
      assert_equal 'basic', app.create_request_token(user, 'http://localhost/cb').scope
    end

    test 'a request token expires, and the default lifetime is ten minutes' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')

      assert_equal 10.minutes.to_i, Platform::Config.oauth_request_token_lifetime
      assert_in_delta (Time.now + 10.minutes).to_i, token.valid_to.to_i, 5
    end

    test 'an expired request token is not a valid token' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic', -1.minute)

      assert_equal false, token.valid_token?
    end

    ##########################################################################
    #### PKCE binding
    ####
    #### Binding the challenge to the code here is what lets the token endpoint prove the client
    #### redeeming the code is the one that requested it, with no shared secret.  RFC 6749
    #### section 2.1 / RFC 9700 section 2.1.1.
    ##########################################################################

    test 'create_request_token binds a PKCE challenge to the code' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic', 10.minutes,
                                       code_challenge: 'abc123',
                                       code_challenge_method: 'S256')

      assert_equal 'abc123', token.reload.code_challenge
      assert_equal 'S256',   token.code_challenge_method
    end

    test 'no PKCE challenge is bound when the authorize request did not send one' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')

      assert_nil token.reload.code_challenge
      assert_nil token.code_challenge_method
    end

    ##########################################################################
    #### Authorization
    ##########################################################################

    test 'a new request token is not yet authorized' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')

      assert_nil token.authorized?
    end

    test 'authorize! marks the consent given' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')
      token.authorize!

      assert_equal true, token.reload.authorized?
    end

    test 'a request token revoked after consent does not read as authorized' do
      token = app.create_request_token(user, 'http://localhost/cb', 'basic')
      token.authorize!
      token.invalidate!

      assert_equal false, token.authorized?
    end

  end # class RequestTokenTest
end # module Platform::Oauth
