require_relative '../../../../test_helper'

module Platform::Oauth
  class RefreshTokenTest < ActiveRecord::TestCase

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
      original = ActiveRecord::Base.default_timezone
      ActiveRecord::Base.default_timezone = zone
      yield
    ensure
      ActiveRecord::Base.default_timezone = original
    end

    # There is no mocha in this suite, and Platform::Config.oauth answers the live configuration
    # hash, so the value is swapped in place and put back.
    def with_grace_period(seconds)
      oauth    = Platform::Config.oauth
      original = oauth[:refresh_token_grace_period]

      oauth[:refresh_token_grace_period] = seconds
      yield
    ensure
      oauth[:refresh_token_grace_period] = original
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
