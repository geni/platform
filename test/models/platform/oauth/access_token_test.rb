module Platform::Oauth
  class AccessTokenTest < ActiveSupport::TestCase

    test 'user is required' do
      ex = assert_raise ActiveRecord::RecordInvalid do
        AccessToken.create!(:application => app, :token => 'foo')
      end
      assert_match /user.*blank/i, ex.message
    end

  end # class AccessTokenTest
end # module Platform::Oauth
