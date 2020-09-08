require_relative '../../../../test_helper'

module Platform::Oauth
  class AccessTokenTest < ActiveRecord::TestCase

    test 'user is required' do
      ex = assert_raise ActiveRecord::RecordInvalid do 
        AccessToken.create!(:application => app, :token => 'foo')
      end
      assert_match /user.*blank/i, ex.message
    end

    test 'find_by_token finds client tokens' do
      token = ClientToken.create!(:application => app, :user => user, :token => 'foo')
      assert_equal token, AccessToken.find_by_token(token.token)
    end

  end # class AccessTokenTest
end # module Platform::Oauth
