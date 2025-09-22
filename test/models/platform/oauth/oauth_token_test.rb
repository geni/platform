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

  end # class OauthTokenTest
end # module Platform::Oauth
