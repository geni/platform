require 'test_helper'

module Platform::Oauth
  class AccessTokenTest < Platform::TestCase

    test 'user is required' do
      ex = assert_raise ActiveRecord::RecordInvalid do
        AccessToken.create!(application: app, token: 'foo')
      end
      assert_match /user.*blank/i, ex.message
    end

    ##########################################################################
    #### create_access_token
    ##########################################################################

    test 'create_access_token records the user and scope and hands back a usable token' do
      token = app.create_access_token(user, 'user_email')

      assert_equal app.id,  token.application_id
      assert_equal user.id, token.user_id
      assert_equal 'user_email', token.scope
      assert_equal true, token.valid_token?
      assert_not_nil token.client_token
    end

    test 'the scope defaults to basic and the lifetime to the configured API lifetime' do
      token = app.create_access_token(user)

      assert_equal 'basic', token.scope
      assert_in_delta (Time.now + Platform::Config.api_token_lifetime).to_i, token.valid_to.to_i, 5
    end

    # Not in the hashed types list: #find_or_create_access_token reuses a stored access token and
    # returns it to the client, and a digest cannot be turned back into the token that produced
    # it.  Hashing these would mean giving up that reuse.
    test 'an access token is stored in the clear' do
      token = app.create_access_token(user, 'basic')

      assert_equal false, AccessToken.store_digest?
      assert_equal token.token, token.client_token
    end

    ##########################################################################
    #### find_access_token
    ####
    #### How every API call authenticates.  It accepts an access token or a client token, and
    #### must return nil rather than a token for anything that is not currently valid.
    ##########################################################################

    test 'find_access_token authenticates a live access token' do
      token = app.create_access_token(user, 'basic')

      found = Platform::Application.find_access_token(token.client_token)

      assert_equal token.id, found.id
      assert_kind_of AccessToken, found
    end

    test 'find_access_token rejects an invalidated token' do
      token = app.create_access_token(user, 'basic')
      token.invalidate!

      assert_nil Platform::Application.find_access_token(token.client_token)
    end

    test 'find_access_token rejects an expired token' do
      token = app.create_access_token(user, 'basic', -1.minute)

      assert_nil Platform::Application.find_access_token(token.client_token)
    end

    test 'find_access_token rejects a value that is not a token' do
      assert_nil Platform::Application.find_access_token('not a token')
      assert_nil Platform::Application.find_access_token('')
      assert_nil Platform::Application.find_access_token(nil)
    end

    # It looks up access tokens and client tokens only.  A request token is an authorization code
    # -- a one-time credential to be exchanged, not a bearer token -- and a refresh token is for
    # the token endpoint, so neither may authenticate an API call.
    test 'find_access_token does not accept a request or refresh token' do
      request = app.create_request_token(user, 'http://localhost/cb', 'basic')
      refresh = app.create_refresh_token(user, 'basic')

      assert_nil Platform::Application.find_access_token(request.code)
      assert_nil Platform::Application.find_access_token(refresh.client_token)
    end

    ##########################################################################
    #### find_or_create_access_token
    ####
    #### Reuses a stored token for the same application, user and scope rather than minting a new
    #### one per call, and destroys the ones it cannot reuse.
    ##########################################################################

    test 'find_or_create_access_token mints a token when there is none' do
      token = app.find_or_create_access_token(user, 'basic')

      assert_equal user.id, token.user_id
      assert_equal 'basic', token.scope
      assert_equal true, token.valid_token?
    end

    test 'find_or_create_access_token reuses the token it already issued' do
      first  = app.find_or_create_access_token(user, 'basic')
      second = app.find_or_create_access_token(user, 'basic')

      assert_equal first.id, second.id
      assert_equal 1, AccessToken.where(application_id: app.id, user_id: user.id).count
    end

    test 'find_or_create_access_token records the user as an application user' do
      app.find_or_create_access_token(user, 'basic')

      assert_not_nil Platform::ApplicationUser.for(app, user)
    end

    test 'find_or_create_access_token mints a new token for a different scope' do
      basic = app.find_or_create_access_token(user, 'basic')
      email = app.find_or_create_access_token(user, 'user_email')

      assert_not_equal basic.id, email.id
      assert_equal 'user_email', email.scope
    end

    # The loop destroys every token it cannot hand back, so asking for a new scope discards the
    # token issued for the old one -- a client that switches scope loses the token it was using.
    test 'asking for a different scope destroys the token held for the old one' do
      basic = app.find_or_create_access_token(user, 'basic')
      app.find_or_create_access_token(user, 'user_email')

      assert_nil AccessToken.find_by_id(basic.id)
    end

    test 'find_or_create_access_token replaces an expired token' do
      expired = app.create_access_token(user, 'basic', -1.minute)

      token = app.find_or_create_access_token(user, 'basic')

      assert_not_equal expired.id, token.id
      assert_equal true, token.valid_token?
      assert_nil AccessToken.find_by_id(expired.id), 'the expired token is destroyed, not kept'
    end

    test 'find_or_create_access_token replaces an invalidated token' do
      revoked = app.create_access_token(user, 'basic')
      revoked.invalidate!

      token = app.find_or_create_access_token(user, 'basic')

      assert_not_equal revoked.id, token.id
      assert_nil AccessToken.find_by_id(revoked.id)
    end

    # Only the first reusable token is kept; the rest are destroyed, so repeated calls converge
    # on a single row per application and user.
    test 'find_or_create_access_token collapses duplicate tokens down to one' do
      app.create_access_token(user, 'basic')
      app.create_access_token(user, 'basic')
      app.create_access_token(user, 'basic')

      token = app.find_or_create_access_token(user, 'basic')

      assert_equal 1, AccessToken.where(application_id: app.id, user_id: user.id).count
      assert_equal token.id, AccessToken.where(application_id: app.id, user_id: user.id).first.id
    end

    test 'find_or_create_access_token is scoped to the user and the application' do
      mine   = app.find_or_create_access_token(user, 'basic')
      theirs = app.find_or_create_access_token(create_user('someone else'), 'basic')
      other  = create_app(name: 'Other').find_or_create_access_token(user, 'basic')

      assert_equal 3, [mine.id, theirs.id, other.id].uniq.size
    end

    ##########################################################################
    #### invalidate_all_access_tokens
    ##########################################################################

    test 'invalidate_all_access_tokens invalidates this user access tokens' do
      one = app.create_access_token(user, 'basic')
      two = app.create_access_token(user, 'user_email')

      app.invalidate_all_access_tokens(user)

      assert_equal true, one.reload.invalidated?
      assert_equal true, two.reload.invalidated?
    end

    test 'invalidate_all_access_tokens leaves other users and applications alone' do
      other_user = create_user('someone else')
      theirs     = app.create_access_token(other_user, 'basic')
      elsewhere  = create_app(name: 'Other').create_access_token(user, 'basic')

      app.invalidate_all_access_tokens(user)

      assert_equal false, theirs.reload.invalidated?
      assert_equal false, elsewhere.reload.invalidated?
    end

    # Access tokens only -- a refresh token survives, which is why the replay and deauthorization
    # paths go through OauthToken.revoke_all_for instead.
    test 'invalidate_all_access_tokens does not reach the refresh token' do
      refresh = app.create_refresh_token(user, 'basic')
      app.create_access_token(user, 'basic')

      app.invalidate_all_access_tokens(user)

      assert_equal false, refresh.reload.invalidated?
    end

  end # class AccessTokenTest
end # module Platform::Oauth
