require 'test_helper'

module Platform::Oauth
  class ClientTokenTest < Platform::TestCase

    # The client_credentials grant is server-to-server, so this is the one token type that is
    # meant to have no user.  Making `belongs_to :user` required on the base class turned the
    # whole grant into a RecordInvalid, which is why that association is :optional.
    test 'a client token has no user' do
      token = app.create_client_token('basic')

      assert_nil token.reload.user_id
      assert_equal true, token.valid?
    end

    test 'create_client_token mints a usable token with the requested scope' do
      token = app.create_client_token('basic')

      assert_equal app.id,  token.application_id
      assert_equal 'basic', token.scope
      assert_equal true,    token.valid_token?
      assert_not_nil token.client_token
    end

    test 'create_client_token expires in an hour by default' do
      token = app.create_client_token('basic')

      assert_in_delta (Time.now + 1.hour).to_i, token.valid_to.to_i, 5
    end

    test 'the lifetime can be overridden' do
      token = app.create_client_token('basic', 5.minutes)

      assert_in_delta (Time.now + 5.minutes).to_i, token.valid_to.to_i, 5
    end

    # Not in the hashed types list, because Application#find_access_token looks client tokens up
    # the same way it looks access tokens up and a digest cannot be turned back into the token
    # that produced it.
    test 'a client token is stored in the clear' do
      token = app.create_client_token('basic')

      assert_equal false, ClientToken.store_digest?
      assert_equal token.token, token.client_token
    end

    test 'code is the value handed to the client' do
      token = app.create_client_token('basic')

      assert_equal token.client_token, token.code
    end

    test 'a client token authenticates through find_access_token' do
      token = app.create_client_token('basic')

      found = Platform::Application.find_access_token(token.client_token)

      assert_not_nil found
      assert_equal token.id, found.id
      assert_kind_of ClientToken, found
    end

    test 'an invalidated client token no longer authenticates' do
      token = app.create_client_token('basic')
      token.invalidate!

      assert_nil Platform::Application.find_access_token(token.client_token)
    end

    test 'an expired client token no longer authenticates' do
      token = app.create_client_token('basic', -1.minute)

      assert_nil Platform::Application.find_access_token(token.client_token)
    end

    # Every application may ask for one, so there is no flag gating this grant.
    test 'the client_credentials grant is allowed for every application' do
      assert_equal true, app.allow_grant_type_client_credentials?
    end

  end # class ClientTokenTest
end # module Platform::Oauth
