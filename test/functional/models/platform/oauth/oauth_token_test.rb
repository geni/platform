require_relative '../../../../test_helper'

module Platform::Oauth
  class OauthTokenTest < ActiveRecord::TestCase

    # Ticket 19802
    test 'valid_to' do
      token = OauthToken.create!(:application => app, :token => "foo_#{Time.now.to_f}", :expire_in => 1.minute)
      assert !token.valid_to.nil?
    end

    # Ticket 19802
    test 'to_json' do
      token = OauthToken.create!(:application => app, :token => "foo_#{Time.now.to_f}")
      json = token.to_json
      assert_match token.token, json
      assert_match 'expires_in', json
    end

    # Ticket 19802
    test 'invalidate! sets invalidated_at' do
      token = OauthToken.create!(:application => app, :token => "foo_#{Time.now.to_f}")
      token.valid_to = Time.now - 5.minutes  # not in create (not safe to mass-assign)
      token.save!
      assert  token.invalidated_at.nil?
      assert  token.invalidate!
      assert !token.invalidated_at.nil?
    end

    ##########################################################################
    #### find_by_presented_token
    ##########################################################################

    test 'find_by_presented_token finds a digested token by its cleartext' do
      raw = app.create_refresh_token(user, 'basic').client_token

      found = RefreshToken.find_by_presented_token(raw)

      assert_not_nil found
      assert_equal raw, found.raw_token, 'the cleartext is attached to the record that was found'
      assert_equal raw, found.client_token
    end

    test 'find_by_presented_token finds a cleartext token' do
      raw = app.create_access_token(user, 'basic').client_token

      found = AccessToken.find_by_presented_token(raw)

      assert_not_nil found
      assert_equal raw, found.raw_token
    end

    test 'find_by_presented_token rejects a blank or missing value' do
      assert_nil AccessToken.find_by_presented_token(nil)
      assert_nil AccessToken.find_by_presented_token('')
    end

    ##########################################################################
    #### Presenting the stored digest
    ####
    #### #find_by_presented_token tries the digest first and then, while
    #### oauth_allow_cleartext_token_lookup? is on, the value as presented.  Nothing used to
    #### distinguish the two lookups by shape, so the second one matched a *digest* presented as
    #### though it were a token -- and a digest is exactly what someone reading this table has.
    ####
    #### Two things followed, and both are what these tests hold shut:
    ####
    ####   * it authenticated, so hashing at rest bought nothing while
    ####     allow_cleartext_token_lookup was on -- and it defaults to on, and has to stay on
    ####     while pre-hashing rows are in play, which is the whole transition window;
    ####   * the lookup then ran #upgrade_stored_token_to_digest!, rewriting the row as
    ####     digest(digest), so the legitimate holder's real token stopped working.  One request
    ####     with a known digest revoked the token it named.
    ##########################################################################

    test 'find_by_presented_token does not find the digest itself' do
      raw    = app.create_refresh_token(user, 'basic').client_token
      digest = Platform::Helper.token_digest(raw)

      assert_nil RefreshToken.find_by_presented_token(digest),
                 'presenting the stored digest must not authenticate'
    end

    test 'presenting the digest does not disturb the row, so the real token still works' do
      token  = app.create_refresh_token(user, 'basic')
      raw    = token.client_token
      stored = token.token

      RefreshToken.find_by_presented_token(Platform::Helper.token_digest(raw))

      assert_equal stored, token.reload.token, 'the row must not be re-digested'
      assert_not_nil RefreshToken.find_by_presented_token(raw),
                     'the holder of the real token can still use it'
    end

    # The guard is scoped to the digested types.  A type stored in the clear has no digest in the
    # column for a presented value to collide with, so refusing digest-width values there would
    # reject a legacy token that happened to be 43 characters for no gain.
    test 'a cleartext type still accepts a token of digest width' do
      raw = Platform::Helper.generate_token(Platform::Helper::TOKEN_DIGEST_LENGTH)
      AccessToken.create!(:application => app, :user => user, :token => raw)

      assert_equal false, AccessToken.store_digest?
      assert_not_nil AccessToken.find_by_presented_token(raw)
    end

    test 'a digested type still accepts a legacy cleartext token of ordinary width' do
      raw = Platform::Helper.generate_token(40)
      RefreshToken.create!(:application => app, :user => user, :token => raw)

      assert_not_nil RefreshToken.find_by_presented_token(raw),
                     'the guard must not break the pre-hashing rows the cleartext arm is for'
    end

    test 'the digest length constant matches what token_digest produces' do
      assert_equal 43, Platform::Helper::TOKEN_DIGEST_LENGTH
      assert_equal 43, Platform::Helper.token_digest('anything').length
      assert_equal true,  Platform::Helper.token_digest_shaped?(Platform::Helper.token_digest('x'))
      assert_equal false, Platform::Helper.token_digest_shaped?(Platform::Helper.generate_token(40))
    end

    # Turning the cleartext lookup off is the end state: once no pre-hashing rows remain, the
    # digest arm is the only one left.
    test 'the digest is not accepted once the cleartext lookup is off' do
      token  = app.create_refresh_token(user, 'basic')
      digest = Platform::Helper.token_digest(token.client_token)

      with_cleartext_lookup(false) do
        assert_nil RefreshToken.find_by_presented_token(digest)
      end
    end

    ##########################################################################
    #### live_tokens_for and revoke_all_for
    ####
    #### Refresh tokens were permanent credentials until this gem started setting valid_to, so
    #### production holds millions of unexpiring rows: 4.3M on one application and member, 205k on
    #### the next.  .live_tokens_for answered with every one of them, and .revoke_all_for built an
    #### ActiveRecord object for each -- inside a request, reached from RefreshToken#replay!.  One
    #### refresh token presented twice was an out-of-memory kill.
    ##########################################################################

    test 'live_tokens_for does not answer with an expired token' do
      live    = app.create_access_token(user)
      expired = app.create_access_token(user)
      expired.expire_in!(-1.hour)

      ids = OauthToken.live_tokens_for(app.id, user.id).map { |t| t.id }

      assert        ids.include?(live.id)
      assert_equal false, ids.include?(expired.id), 'an expired token is not live'
    end

    test 'live_tokens_for does not answer with an invalidated token' do
      revoked = app.create_access_token(user)
      revoked.invalidate!

      ids = OauthToken.live_tokens_for(app.id, user.id).map { |t| t.id }

      assert_equal false, ids.include?(revoked.id)
    end

    # A token with no expiry is still live -- that is what the pre-valid_to rows are, and revoking
    # them is the whole point of the sweep.
    test 'live_tokens_for answers with a token that has no expiry' do
      forever = app.create_access_token(user)
      clear_expiry(forever)

      ids = OauthToken.live_tokens_for(app.id, user.id).map { |t| t.id }

      assert ids.include?(forever.id)
    end

    test 'live_tokens_for honours a limit' do
      3.times { app.create_access_token(user) }

      assert_equal 2, OauthToken.live_tokens_for(app.id, user.id, 2).size
    end

    # The user_id IS NULL arm, which is the client_credentials path -- and the second worst pair in
    # production, at 205k rows.
    test 'live_tokens_for separates the no-user tokens from a user of their own' do
      client_token = app.create_client_token('basic')
      user_token   = app.create_access_token(user)

      without_user = OauthToken.live_tokens_for(app.id, nil).map { |t| t.id }
      with_user    = OauthToken.live_tokens_for(app.id, user.id).map { |t| t.id }

      assert        without_user.include?(client_token.id)
      assert_equal false, without_user.include?(user_token.id)
      assert        with_user.include?(user_token.id)
      assert_equal false, with_user.include?(client_token.id)
    end

    # More rows than one batch holds, so the loop has to run more than once to drain them.
    test 'revoke_all_for drains more tokens than fit in a single batch' do
      total = OauthToken::REVOKE_BATCH_SIZE + 5
      total.times { app.create_refresh_token(user) }

      revoked = OauthToken.revoke_all_for(app.id, user.id)

      assert_equal total, revoked, 'every live token should have been revoked, batch size aside'
      assert_equal [], OauthToken.live_tokens_for(app.id, user.id),
                   'nothing live should be left behind'
    end

    test 'revoke_all_for leaves an expired token alone rather than loading it' do
      expired = app.create_refresh_token(user)
      expired.expire_in!(-1.hour)

      assert_equal 0, OauthToken.revoke_all_for(app.id, user.id),
                   'an expired token is already unusable and must not be loaded to revoke it'
      assert_nil expired.reload.invalidated_at
    end

    test 'revoke_all_for counts nothing when there is nothing live' do
      assert_equal 0, OauthToken.revoke_all_for(app.id, user.id)
    end

private

    # There is no mocha in this suite, so the accessor itself is swapped out and put back -- the
    # same reason RefreshTokenTest#with_grace_period does it this way rather than writing into the
    # hash Platform::Config.oauth answers.
    # Makes a row look like one written before this gem set valid_to at all, which is what the
    # millions of rows in production are and what .live_tokens_for has to keep answering with.
    #
    # An UPDATE rather than #update_attribute(:valid_to, nil).  Dirty tracking on activesupport 3.1
    # compares the stored ActiveSupport::TimeWithZone to the new nil with <=>, which calls
    # #to_datetime on nil and raises NoMethodError -- so the assignment form passes on 2.3 and 3.0
    # and blows up from 3.1 on.  Writing the column directly means the same thing on every branch,
    # and is closer to how those rows came to exist in the first place.
    def clear_expiry(token)
      token.class.connection.update(
        "UPDATE #{token.class.table_name} SET valid_to = NULL WHERE id = #{token.id.to_i}")
      token.reload
    end

    def with_cleartext_lookup(value)
      singleton = Platform::Config.singleton_class

      singleton.send(:alias_method, :cleartext_lookup_before_stub, :oauth_allow_cleartext_token_lookup?)
      singleton.send(:define_method, :oauth_allow_cleartext_token_lookup?) { value }
      yield
    ensure
      singleton.send(:alias_method, :oauth_allow_cleartext_token_lookup?, :cleartext_lookup_before_stub)
      singleton.send(:remove_method, :cleartext_lookup_before_stub)
    end

  end # class OauthTokenTest
end # module Platform::Oauth
