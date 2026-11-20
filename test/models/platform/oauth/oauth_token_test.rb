require 'test_helper'

module Platform::Oauth
  class OauthTokenTest < Platform::TestCase

    ##########################################################################
    #### Validations
    ##########################################################################

    test 'an application and a token value are required' do
      ex = assert_raise ActiveRecord::RecordInvalid do
        OauthToken.create!(user: user, token: 'foo')
      end
      assert_match(/application/i, ex.message)

      ex = assert_raise ActiveRecord::RecordInvalid do
        OauthToken.create!(application: app, user: user)
      end
      assert_match(/token.*blank/i, ex.message)
    end

    test 'the token value is unique' do
      OauthToken.create!(application: app, user: user, token: 'foo')

      ex = assert_raise ActiveRecord::RecordInvalid do
        OauthToken.create!(application: app, user: user, token: 'foo')
      end
      assert_match(/token.*taken/i, ex.message)
    end

    # The base class has no user, by design: the client_credentials grant is server-to-server.
    # The subclasses that do need one say so themselves -- see access_token_test.rb and
    # request_token_test.rb.
    test 'the base class does not require a user' do
      token = OauthToken.create!(application: app, token: 'foo')

      assert_nil token.reload.user
    end

    ##########################################################################
    #### Expiry
    ##########################################################################

    # Ticket 19802
    test 'valid_to' do
      token = OauthToken.create!(application: app, user: user, token: 'foo', expire_in: 1.minute)
      assert !token.valid_to.nil?
    end

    test 'expire_in sets valid_to that far ahead' do
      token = OauthToken.new(application: app, user: user, token: 'foo')
      token.expire_in(1.hour)

      assert_in_delta (Time.now + 1.hour).to_i, token.valid_to.to_i, 5
    end

    # #expire_in returning early on nil is what let every refresh token ever issued be permanent:
    # Application#create_refresh_token used to default its interval to nil.  The behaviour is
    # still here and still correct for a token that is meant not to expire, so it is the caller
    # that has to pass a lifetime.
    test 'expire_in with nil leaves valid_to unset' do
      token = OauthToken.new(application: app, user: user, token: 'foo')
      token.expire_in(nil)

      assert_nil token.valid_to
    end

    test 'expire_in! saves' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      token.expire_in!(1.hour)

      assert_not_nil token.reload.valid_to
    end

    ##########################################################################
    #### valid_token?
    ####
    #### The gate Platform::Application.find_access_token puts every presented access token
    #### through, so each arm of it is a way in.
    ##########################################################################

    test 'a fresh token with no expiry is valid' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')

      assert_equal true, token.valid_token?
    end

    test 'an invalidated token is not valid' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      token.invalidate!

      assert_equal false, token.valid_token?
    end

    test 'an expired token is not valid' do
      token = OauthToken.create!(application: app, user: user, token: 'foo',
                                 valid_to: 1.minute.ago)

      assert_equal false, token.valid_token?
    end

    test 'a token whose expiry is still ahead is valid' do
      token = OauthToken.create!(application: app, user: user, token: 'foo',
                                 valid_to: 1.minute.from_now)

      assert_equal true, token.valid_token?
    end

    test 'valid_token? checks the scope when one is asked for' do
      token = OauthToken.create!(application: app, user: user, token: 'foo', scope: 'basic')

      assert_equal true,  token.valid_token?('basic')
      assert_equal false, token.valid_token?('user_email')
      assert_equal true,  token.valid_token?, 'no requested scope means no scope check'
    end

    # The comparison is a string equality against the whole stored scope, not a subset test, so a
    # token carrying two scopes does not satisfy a request for one of them.  That is what
    # Application#find_or_create_access_token relies on to decide a stored token is not reusable.
    test 'valid_token? compares the scope string whole' do
      token = OauthToken.create!(application: app, user: user, token: 'foo',
                                 scope: 'user_basic,user_email')

      assert_equal false, token.valid_token?('user_basic')
      assert_equal true,  token.valid_token?('user_basic,user_email')
    end

    ##########################################################################
    #### Invalidation and authorization
    ##########################################################################

    # Ticket 19802
    test 'invalidate! sets invalidated_at' do
      token = OauthToken.create!(application: app, user: user, token: 'foo', valid_to: Time.now - 5.minutes)
      assert  token.invalidated_at.nil?
      assert  token.invalidate!
      assert !token.invalidated_at.nil?
    end

    test 'invalidate sets the timestamp without saving' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      token.invalidate

      assert_equal true, token.invalidated?
      assert_nil token.reload.invalidated_at, 'the unsaved change is not in the database'
    end

    test 'invalidated? reads the timestamp' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')

      assert_equal false, token.invalidated?
      token.invalidate!
      assert_equal true,  token.invalidated?
    end

    test 'authorize! sets authorized_at' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      assert_nil token.authorized_at

      token.authorize!

      assert_not_nil token.reload.authorized_at
      assert_equal true, token.authorized?
    end

    test 'authorize sets the timestamp without saving' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      token.authorize

      assert_equal true, token.authorized?
      assert_nil token.reload.authorized_at
    end

    # #authorized? is not simply "has it been authorized": an authorization that was later
    # withdrawn must not read as authorized, which is what makes a revoked authorization code
    # unredeemable.
    test 'an invalidated token is not authorized, even once it has been' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      token.authorize!
      assert_equal true, token.authorized?

      token.invalidate!

      assert_equal false, token.authorized?
    end

    test 'a token that was never authorized is not authorized' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')

      assert_nil token.authorized?, 'authorized_at is nil, and #authorized? returns it'
    end

    ##########################################################################
    #### Token values and digests
    ####
    #### What is in the token column is a digest for some token types and the cleartext for
    #### others, and the difference decides whether a token can be handed back to a client at all.
    ##########################################################################

    test 'store_digest? follows the configured list of hashed types' do
      assert_equal true,  RequestToken.store_digest?
      assert_equal true,  RefreshToken.store_digest?
      assert_equal false, AccessToken.store_digest?,  'reused by find_or_create_access_token'
      assert_equal false, ClientToken.store_digest?
      assert_equal false, OauthToken.store_digest?
    end

    test 'generate_key stores the cleartext for a type that is not digested' do
      token = AccessToken.new(application: app, user: user)
      raw   = token.generate_key

      assert_equal 40, raw.length
      assert_match(/\A[A-Za-z0-9]{40}\z/, raw)
      assert_equal raw, token.token
      assert_equal raw, token.raw_token
      assert_equal raw, token.client_token
    end

    test 'generate_key stores a digest for a type that is digested' do
      token = RefreshToken.new(application: app, user: user)
      raw   = token.generate_key

      assert_not_equal raw, token.token
      assert_equal Platform::Helper.token_digest(raw), token.token
      assert_equal raw, token.raw_token, 'the cleartext is kept in memory for this process'
      assert_equal raw, token.client_token
    end

    test 'generate_key produces a different token each time' do
      first  = AccessToken.new(application: app, user: user).generate_key
      second = AccessToken.new(application: app, user: user).generate_key

      assert_not_equal first, second
    end

    # The digest is 43 characters and a generated token is 40, so both fit the varchar(50) column
    # and the two lookups in #find_by_presented_token cannot collide.
    test 'a stored digest fits the token column and cannot be mistaken for a token' do
      token = RefreshToken.new(application: app, user: user)
      token.generate_key

      assert_equal 43, token.token.length
      assert_operator token.token.length, :<=, 50
    end

    # The reason #client_token exists rather than callers reading #token: handing back the digest
    # would give the client a string that looks like a token and can never authenticate.
    test 'client_token is nil for a digested token loaded from the database' do
      raw   = app.create_refresh_token(user, 'basic').client_token
      found = RefreshToken.find_by_token(Platform::Helper.token_digest(raw))

      assert_not_nil found
      assert_nil found.raw_token
      assert_nil found.client_token
    end

    test 'client_token falls back to the stored value for a type that is not digested' do
      raw   = app.create_access_token(user, 'basic').client_token
      found = AccessToken.find_by_token(raw)

      assert_nil found.raw_token
      assert_equal raw, found.client_token
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
      AccessToken.create!(application: app, user: user, token: raw)

      assert_equal false, AccessToken.store_digest?
      assert_not_nil AccessToken.find_by_presented_token(raw)
    end

    test 'a digested type still accepts a legacy cleartext token of ordinary width' do
      raw = Platform::Helper.generate_token(40)
      RefreshToken.create!(application: app, user: user, token: raw)

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

    test 'find_by_presented_token rejects a blank or missing value' do
      assert_nil AccessToken.find_by_presented_token(nil)
      assert_nil AccessToken.find_by_presented_token('')
      assert_nil AccessToken.find_by_presented_token('not a token')
    end

    test 'find_by_presented_token is scoped to its own token type' do
      raw = app.create_access_token(user, 'basic').client_token

      assert_not_nil AccessToken.find_by_presented_token(raw)
      assert_nil     RefreshToken.find_by_presented_token(raw)
    end

    ##########################################################################
    #### Upgrading a cleartext row to a digest
    ####
    #### How the table converts itself while hashing is being rolled out: a row written before
    #### the switch is still found by its cleartext, and that lookup rewrites it.
    ##########################################################################

    test 'a cleartext row of a digested type is rewritten as a digest when it is presented' do
      raw = Platform::Helper.generate_token(40)
      RefreshToken.create!(application: app, user: user, token: raw)

      found = RefreshToken.find_by_presented_token(raw)

      assert_not_nil found, 'the cleartext lookup is what keeps pre-hashing rows working'
      assert_equal Platform::Helper.token_digest(raw), found.reload.token
      assert_nil   RefreshToken.find_by_token(raw), 'the cleartext value is gone from the column'
    end

    test 'the rewritten row is still found by the same presented value afterwards' do
      raw = Platform::Helper.generate_token(40)
      RefreshToken.create!(application: app, user: user, token: raw)
      RefreshToken.find_by_presented_token(raw)

      assert_not_nil RefreshToken.find_by_presented_token(raw)
    end

    test 'the cleartext lookup can be switched off once the tail has aged out' do
      raw = Platform::Helper.generate_token(40)
      RefreshToken.create!(application: app, user: user, token: raw)

      with_cleartext_lookup(false) do
        assert_nil RefreshToken.find_by_presented_token(raw)
      end
    end

    test 'switching the cleartext lookup off does not break a digested row' do
      raw = app.create_refresh_token(user, 'basic').client_token

      with_cleartext_lookup(false) do
        assert_not_nil RefreshToken.find_by_presented_token(raw)
      end
    end

    test 'upgrade_stored_token_to_digest! does nothing for a type that is not digested' do
      token = app.create_access_token(user, 'basic')
      was   = token.token

      assert_equal false, token.upgrade_stored_token_to_digest!
      assert_equal was, token.reload.token
    end

    test 'upgrade_stored_token_to_digest! does nothing without the cleartext in hand' do
      raw   = app.create_refresh_token(user, 'basic').client_token
      found = RefreshToken.find_by_token(Platform::Helper.token_digest(raw))

      assert_nil found.raw_token
      assert_equal false, found.upgrade_stored_token_to_digest!
    end

    ##########################################################################
    #### to_json
    ##########################################################################

    # Ticket 19802
    test 'to_json' do
      token = OauthToken.create!(application: app, user: user, token: 'foo')
      json = token.to_json
      assert_match token.token, json
      assert_match 'expires_in', json
    end

    test 'to_json hands back the client token, not the stored digest' do
      token = app.create_refresh_token(user, 'basic')
      json  = JSON.parse(token.to_json)

      assert_equal token.client_token, json['access_token']
      assert_not_equal token.token, json['access_token']
    end

    test 'to_json reports the seconds remaining' do
      token = app.create_access_token(user, 'basic', 1.hour)
      json  = JSON.parse(token.to_json)

      assert_in_delta 3600, json['expires_in'], 5
    end

    ##########################################################################
    #### live_tokens_for and revoke_all_for
    ####
    #### What a deauthorization, an admin revocation and a refresh-token replay all go through.
    ##########################################################################

    test 'live_tokens_for returns every type of token the application holds for the user' do
      access  = app.create_access_token(user, 'basic')
      refresh = app.create_refresh_token(user, 'basic')
      request = app.create_request_token(user, 'http://localhost', 'basic')

      found = OauthToken.live_tokens_for(app.id, user.id)

      assert_equal [access.id, refresh.id, request.id].sort, found.map(&:id).sort
    end

    # find_by_sql still instantiates through STI, which is what lets #revoke_all_for call each
    # row's own #invalidate! and so fire the host application's cache-flushing callbacks.
    test 'live_tokens_for instantiates each row as its own subclass' do
      app.create_access_token(user, 'basic')
      app.create_refresh_token(user, 'basic')

      classes = OauthToken.live_tokens_for(app.id, user.id).map(&:class)

      assert_equal [AccessToken, RefreshToken], classes.sort_by(&:name)
    end

    test 'live_tokens_for excludes tokens that are already invalidated' do
      live = app.create_access_token(user, 'basic')
      app.create_access_token(user, 'other').invalidate!

      assert_equal [live.id], OauthToken.live_tokens_for(app.id, user.id).map(&:id)
    end

    test 'live_tokens_for is scoped to the application and the user' do
      app.create_access_token(user, 'basic')
      other_app  = create_app(name: 'Other')
      other_user = create_user('someone else')
      other_app.create_access_token(user, 'basic')
      app.create_access_token(other_user, 'basic')

      assert_equal 1, OauthToken.live_tokens_for(app.id, user.id).size
    end

    # A nil user_id has to be matched with IS NULL rather than "= NULL", which is the reason for
    # the separate arm in the query.  These are the client_credentials tokens.
    test 'live_tokens_for with a nil user finds the tokens that have no user' do
      client = app.create_client_token('basic')
      app.create_access_token(user, 'basic')

      found = OauthToken.live_tokens_for(app.id, nil)

      assert_equal [client.id], found.map(&:id)
    end

    test 'revoke_all_for invalidates every live token and reports how many' do
      access  = app.create_access_token(user, 'basic')
      refresh = app.create_refresh_token(user, 'basic')

      assert_equal 2, OauthToken.revoke_all_for(app.id, user.id)
      assert_equal true, access.reload.invalidated?
      assert_equal true, refresh.reload.invalidated?
    end

    test 'revoke_all_for leaves other applications and users alone' do
      mine       = app.create_access_token(user, 'basic')
      other_user = create_user('someone else')
      theirs     = app.create_access_token(other_user, 'basic')
      other_app  = create_app(name: 'Other').create_access_token(user, 'basic')

      OauthToken.revoke_all_for(app.id, user.id)

      assert_equal true,  mine.reload.invalidated?
      assert_equal false, theirs.reload.invalidated?
      assert_equal false, other_app.reload.invalidated?
    end

    test 'revoke_all_for is a no-op when there is nothing live' do
      app.create_access_token(user, 'basic').invalidate!

      assert_equal 0, OauthToken.revoke_all_for(app.id, user.id)
    end

    test 'revoke_all_for with a nil user revokes the client_credentials tokens' do
      client = app.create_client_token('basic')
      access = app.create_access_token(user, 'basic')

      assert_equal 1, OauthToken.revoke_all_for(app.id, nil)
      assert_equal true,  client.reload.invalidated?
      assert_equal false, access.reload.invalidated?
    end

    ##########################################################################
    #### Associations
    ##########################################################################

    test 'tokens are destroyed with their application' do
      app.create_access_token(user, 'basic')
      app.create_refresh_token(user, 'basic')
      application_id = app.id

      app.destroy

      assert_equal 0, OauthToken.where(application_id: application_id).count
    end

private

    def with_cleartext_lookup(value)
      Platform::Config.stubs(:oauth_allow_cleartext_token_lookup?).returns(value)
      yield
    end

  end # class OauthTokenTest
end # module Platform::Oauth
