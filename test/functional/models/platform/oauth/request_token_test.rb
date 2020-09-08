require_relative '../../../../test_helper'

module Platform::Oauth
  class RequestTokenTest < ActiveRecord::TestCase

    test 'authorize with user' do
      token = RequestToken.create(:application => app, :user => user, :token => 'foo')
      token.authorize!
      assert_equal @user, token.reload.user
    end

    test 'authorize with profile' do
      token = RequestToken.create(:application => app, :user => user, :token => 'foo')
      token.authorize!
      assert_equal @user, token.reload.user
    end

  end # class RequestTokenTest
end # module Platform::Oauth
