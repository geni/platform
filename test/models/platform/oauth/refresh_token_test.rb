require 'test_helper'

module Platform::Oauth
  class RefreshTokenTest < Platform::TestCase

    ##########################################################################
    #### exchange!
    ####
    #### Rotation: redeeming a refresh token invalidates it and issues a replacement, which is
    #### what makes a second presentation detectable as a replay.
    ##########################################################################

    test 'exchange! issues an access token for the user and spends the refresh token' do
      refresh = app.create_refresh_token(user, 'basic')

      access = refresh.exchange!

      assert_kind_of AccessToken, access
      assert_equal user.id, access.user_id
      assert_equal app.id,  access.application_id
      assert_equal 'basic', access.scope
      assert_equal true,    refresh.reload.invalidated?
    end

    test 'exchange! carries the scope onto the new token' do
      refresh = app.create_refresh_token(user, 'user_basic,user_email')

      assert_equal 'user_basic,user_email', refresh.exchange!.scope
    end

    # A refresh token with no user came from the client_credentials grant, which is
    # server-to-server; exchanging it has to produce another client token, not an access token
    # with a nil user -- which would not validate anyway, since AccessToken requires a user.
    test 'exchange! issues a client token when there is no user' do
      refresh = app.create_refresh_token(nil, 'basic')

      token = refresh.exchange!

      assert_kind_of ClientToken, token
      assert_nil token.user_id
      assert_equal true, refresh.reload.invalidated?
    end

    test 'exchange! hands back a usable token' do
      access = app.create_refresh_token(user, 'basic').exchange!

      assert_not_nil access.client_token
      assert_equal access.id, Platform::Application.find_access_token(access.client_token).id
    end

    ##########################################################################
    #### exchanged! and replayed?
    ##########################################################################

    test 'exchanged! records the redemption and invalidates in one step' do
      refresh = app.create_refresh_token(user, 'basic')

      refresh.exchanged!

      assert_not_nil refresh.reload.exchanged_at
      assert_equal true, refresh.invalidated?
      assert_equal true, refresh.replayed?
    end

    test 'a fresh token has not been replayed' do
      refresh = app.create_refresh_token(user, 'basic')

      assert_equal false, refresh.replayed?
    end

    test 'exchange! marks the token as exchanged' do
      refresh = app.create_refresh_token(user, 'basic')
      refresh.exchange!

      assert_equal true, refresh.reload.replayed?
    end

    # The distinction #replayed? exists for.  A refresh token is also invalidated when the user
    # deauthorizes the application, when an admin revokes it, and when a family revocation sweeps
    # it up.  Reading "invalidated" as "replayed" would report an attack every time a client used
    # a credential that had simply been withdrawn.
    test 'a revoked token that was never exchanged is not a replay' do
      refresh = app.create_refresh_token(user, 'basic')
      refresh.invalidate!

      assert_equal true,  refresh.invalidated?
      assert_equal false, refresh.replayed?
    end

    test 'a token swept up by a family revocation is not a replay' do
      refresh = app.create_refresh_token(user, 'basic')
      OauthToken.revoke_all_for(app.id, user.id)

      assert_equal true,  refresh.reload.invalidated?
      assert_equal false, refresh.replayed?
    end

    ##########################################################################
    #### replay!
    ####
    #### RFC 9700 section 4.14.2: a second presentation of a redeemed refresh token means two
    #### parties hold it and we cannot tell which is the legitimate client, so the whole family
    #### goes rather than guessing.
    ##########################################################################

    test 'replay! revokes every token the application holds for the user' do
      refresh = app.create_refresh_token(user, 'basic')
      access  = app.create_access_token(user, 'basic')
      other   = app.create_refresh_token(user, 'basic')
      refresh.exchange!

      refresh.replay!

      assert_equal true, access.reload.invalidated?
      assert_equal true, other.reload.invalidated?
    end

    test 'replay! does not touch another user or another application' do
      refresh    = app.create_refresh_token(user, 'basic')
      other_user = create_user('someone else')
      theirs     = app.create_access_token(other_user, 'basic')
      other_app  = create_app(name: 'Other').create_access_token(user, 'basic')

      refresh.replay!

      assert_equal false, theirs.reload.invalidated?
      assert_equal false, other_app.reload.invalidated?
    end

    test 'replay! reports how many tokens it revoked' do
      refresh = app.create_refresh_token(user, 'basic')
      app.create_access_token(user, 'basic')

      assert_equal 2, refresh.replay!
    end

    # A replayed client_credentials token has a nil user, and the revocation has to match that
    # with IS NULL rather than sweeping up every token with a user.
    test 'replay! of a token with no user revokes the tokens that have no user' do
      refresh = app.create_refresh_token(nil, 'basic')
      client  = app.create_client_token('basic')
      access  = app.create_access_token(user, 'basic')
      refresh.exchange!

      refresh.replay!

      assert_equal true,  client.reload.invalidated?
      assert_equal false, access.reload.invalidated?
    end

    ##########################################################################
    #### Expiry
    ####
    #### These defaulted to no expiry at all, because Application#create_refresh_token defaulted
    #### its interval to nil and #expire_in returns immediately on nil -- so every refresh token
    #### ever handed out was a permanent credential.
    ##########################################################################

    test 'a refresh token is created with a lifetime' do
      refresh = app.create_refresh_token(user, 'basic')

      assert_not_nil refresh.valid_to
      assert_in_delta (Time.now + Platform::Config.oauth_refresh_token_lifetime).to_i,
                      refresh.valid_to.to_i, 5
    end

    test 'the configured lifetime is 90 days by default' do
      assert_equal 90.days.to_i, Platform::Config.oauth_refresh_token_lifetime
    end

    test 'an expired refresh token is not a valid token' do
      refresh = app.create_refresh_token(user, 'basic', -1.minute)

      assert_equal false, refresh.valid_token?
    end

    ##########################################################################

    test 'redirect_url reads the callback url' do
      refresh = app.create_refresh_token(user, 'basic')
      refresh.update!(callback_url: 'http://localhost/done')

      assert_equal 'http://localhost/done', refresh.redirect_url
    end

    test 'a refresh token is stored as a digest' do
      refresh = app.create_refresh_token(user, 'basic')

      assert_equal true, RefreshToken.store_digest?
      assert_not_equal refresh.client_token, refresh.token
      assert_equal Platform::Helper.token_digest(refresh.client_token), refresh.token
    end

  end # class RefreshTokenTest
end # module Platform::Oauth
