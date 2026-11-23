require_relative '../../../../test_helper'

module Platform::Oauth
  class OauthTokenTest < ActiveRecord::TestCase

    # Ticket 19802
    test 'valid_to' do
      token = OauthToken.create!(:application => app, :token => 'foo', :expire_in => 1.minute)
      assert !token.valid_to.nil?
    end

    # Ticket 19802
    test 'to_json' do
      token = OauthToken.create!(:application => app, :token => 'foo')
      json = token.to_json
      assert_match token.token, json
      assert_match 'expires_in', json
    end

    # Ticket 19802
    test 'invalidate! sets invalidated_at' do
      token = OauthToken.create!(:application => app, :token => 'foo', :valid_to => Time.now - 5.minutes)
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

private

    # There is no mocha in this suite, so the accessor itself is swapped out and put back -- the
    # same reason RefreshTokenTest#with_grace_period does it this way rather than writing into the
    # hash Platform::Config.oauth answers.
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
