require_relative '../../../test_helper'

module Platform
  class ApplicationTest < ActiveRecord::TestCase

    test 'rate_limited' do
      assert_equal true, app.rate_limited?, 'Apps should be rate limited by default'

      app.rate_limited(false)
      assert_equal false, app.rate_limited?, 'Unable to un-limit app'

      app.rate_limited
      assert_equal true, app.rate_limited?, 'Unable to re-limit app'
    end

    # Ticket 19135
    test 'grant_type_password' do
      assert_equal false, app.allow_grant_type_password?, 'Apps should prevent grant_type_password by default'

      app.allow_grant_type_password
      assert_equal true, app.allow_grant_type_password?, 'Unable to allow grant_type_password'

      app.allow_grant_type_password(false)
      assert_equal false, app.allow_grant_type_password?, 'Unable to disallow grant_type_password'
    end

    # Ticket 19180
    test 'unlimited_models' do
      assert_equal false, app.allow_unlimited_models?, 'Apps should prevent unlimited_models by default'

      app.allow_unlimited_models
      assert_equal true, app.allow_unlimited_models?, 'Unable to allow unlimited_models'

      app.allow_unlimited_models(false)
      assert_equal false, app.allow_unlimited_models?, 'Unable to disallow unlimited_models'
    end

  end # class ApplicationTest
end # module Platform
