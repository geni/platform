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


    ##########################################################################
    #### The grace period
    ####
    #### RFC 9700 section 4.14.2 asks for family revocation when a refresh token is replayed, and
    #### leaves the detection window to the implementation.  Okta's refresh token rotation ships
    #### that allowance as its grace period, and this is the same thing: inside the window the
    #### caller is handed the replacement the token was already exchanged for, outside it the
    #### family goes.
    ##########################################################################

    test 'an unexchanged token is not a replay' do
      token = app.create_refresh_token(user)

      assert !token.replayed?
      assert_nil token.live_replacement
    end

    test 'a token exchanged just now is a retry rather than a replay' do
      token       = app.create_refresh_token(user)
      replacement = app.create_refresh_token(user)

      assert token.claim_for_exchange!(replacement)

      assert_equal replacement.id, token.live_replacement.try(:id)
      assert token.grace_period_retry?
      assert !token.replayed?, 'inside the window this is a retry, not a replay'
    end

    test 'a token exchanged longer ago than the window is a replay' do
      token       = app.create_refresh_token(user)
      replacement = app.create_refresh_token(user)

      assert token.claim_for_exchange!(replacement)
      backdate(token, Platform::Config.oauth_refresh_token_grace_period + 60)

      assert !token.grace_period_retry?
      assert token.replayed?
    end

    # A zero window is how the strict, pre-grace behaviour is restored without a deploy.
    test 'a window of zero makes every second presentation a replay' do
      token       = app.create_refresh_token(user)
      replacement = app.create_refresh_token(user)

      assert token.claim_for_exchange!(replacement)

      with_grace_period(0) do
        assert !token.grace_period_retry?
        assert token.replayed?
      end
    end

    # The replacement's liveness is what says the grant still stands, so a replacement that has
    # itself been spent or revoked leaves nothing to vouch for the retry -- and that is a replay.
    test 'a spent replacement is not handed back' do
      token       = app.create_refresh_token(user)
      replacement = app.create_refresh_token(user)
      second      = app.create_refresh_token(user)

      assert token.claim_for_exchange!(replacement)
      assert replacement.claim_for_exchange!(second)

      assert_nil token.live_replacement
      assert token.replayed?
    end

    test 'a revoked replacement is not handed back' do
      token       = app.create_refresh_token(user)
      replacement = app.create_refresh_token(user)

      assert token.claim_for_exchange!(replacement)
      replacement.invalidate!

      assert_nil token.live_replacement
      assert token.replayed?, 'a revoked grant is not retryable'
    end

    # An ordinary revocation is not a replay: the user deauthorized the application, or an admin
    # revoked it, or a family revocation swept this row up.  Reporting those as attacks would make
    # every withdrawn credential look like one.
    test 'an invalidated but never exchanged token is not a replay' do
      token = app.create_refresh_token(user)
      token.invalidate!

      assert !token.replayed?
    end


    # The bug this pins: #claim_for_exchange! writes exchanged_at from raw SQL, and Rails 2.3's
    # #quoted_date converts nothing.  Writing Time.now.utc into a column the app reads as :local
    # stored a reading hours ahead, so #grace_period_retry? measured a negative age and answered
    # true forever -- replay detection silently switched off.  It was the host application's suite
    # that caught it, because both Geni applications configure :local and this gem's own test app
    # does not, so the skew never appeared here.
    #
    # default_timezone is therefore forced for the duration, which is the only way this suite can
    # stand in for the application it ships into.
    test 'a claim records exchanged_at in the zone the column is read back in' do
      with_database_timezone(:local) do
        token       = app.create_refresh_token(user)
        replacement = app.create_refresh_token(user)

        assert token.claim_for_exchange!(replacement)

        skew = Time.now - token.exchanged_at

        assert skew >= 0,   "exchanged_at read back #{skew.to_i}s in the future -- the grace period would never expire"
        assert skew < 300,  "exchanged_at read back #{skew.to_i}s in the past -- the grace period would never apply"
      end
    end

    ##########################################################################
    #### Claiming the exchange
    ##########################################################################

    # #replayed? is a read and the claim is a separate statement, so two requests can both pass the
    # check before either writes.  The conditional UPDATE is what stops both of them minting a
    # family: exactly one flips exchanged_at from NULL.
    test 'only the first claim on a token succeeds' do
      token  = app.create_refresh_token(user)
      first  = app.create_refresh_token(user)
      second = app.create_refresh_token(user)

      assert  token.claim_for_exchange!(first),  'the first claim should win'
      assert !token.claim_for_exchange!(second), 'the second claim should lose'
    end

    # Losing the claim has to leave the loser able to find the winner's replacement, which is the
    # whole reason the claim reloads.
    test 'the loser of a claim sees the winner exchange' do
      token  = app.create_refresh_token(user)
      first  = app.create_refresh_token(user)
      second = app.create_refresh_token(user)

      assert token.claim_for_exchange!(first)

      loser = RefreshToken.find(token.id)
      assert !loser.claim_for_exchange!(second)

      assert_equal first.id, loser.live_replacement.try(:id)
      assert loser.grace_period_retry?, 'the loser is inside the window by construction'
    end

    test 'a claim records the replacement and invalidates the token' do
      token       = app.create_refresh_token(user)
      replacement = app.create_refresh_token(user)

      assert token.claim_for_exchange!(replacement)

      assert_equal replacement.id, token.replaced_by_id
      assert !token.exchanged_at.nil?
      assert !token.invalidated_at.nil?
    end

  private

    def with_database_timezone(zone)
      # Rails 7.0 moved default_timezone off ActiveRecord::Base onto the ActiveRecord module.
      target   = ActiveRecord.respond_to?(:default_timezone) ? ActiveRecord : ActiveRecord::Base
      original = target.default_timezone

      target.default_timezone = zone
      yield
    ensure
      target.default_timezone = original
    end

    # There is no mocha in this suite, so the accessor itself is swapped out and put back.
    #
    # Not by writing into the hash Platform::Config.oauth answers: on activesupport 3.2
    # HashWithIndifferentAccess#[] returns a *converted copy* of a nested hash rather than the
    # stored object, so the write lands on a throwaway and the configured value never changes.
    # That made this test pass for the wrong reason on the branches whose activesupport does hand
    # back the same object.  Overriding the method is the same on every version.
    def with_grace_period(seconds)
      singleton = Platform::Config.singleton_class

      singleton.send(:alias_method, :grace_period_before_stub, :oauth_refresh_token_grace_period)
      singleton.send(:define_method, :oauth_refresh_token_grace_period) { seconds }
      yield
    ensure
      singleton.send(:alias_method, :oauth_refresh_token_grace_period, :grace_period_before_stub)
      singleton.send(:remove_method, :grace_period_before_stub)
    end

    # Moves an exchange back in time.  Written with an UPDATE rather than by assigning, because
    # exchanged_at is set by #claim_for_exchange!'s own statement and a stale object would write it
    # back.
    def backdate(token, seconds)
      when_exchanged = token.class.connection.quoted_date(
                         Platform::Oauth::RefreshToken.now_in_database_timezone - seconds)

      token.class.connection.update(
        "UPDATE #{token.class.table_name} SET exchanged_at = '#{when_exchanged}' WHERE id = #{token.id.to_i}"
      )
      token.reload
    end

  end # class RefreshTokenTest
end # module Platform::Oauth
