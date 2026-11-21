require 'test_helper'

module Platform::Oauth
  class DeviceCodeTest < Platform::TestCase

    ##########################################################################
    #### The user_code
    ##########################################################################

    # The alphabet is the point of this test.  A user_code is read off one screen and typed into
    # another, so O/0 and I/L/1 are the characters people get wrong; RFC 8628 section 6.1 asks for
    # that consideration explicitly.
    test 'user codes avoid the characters people transcribe wrongly' do
      200.times do
        code = Platform::Oauth::DeviceCode.random_user_code

        assert_equal 8, code.length
        assert_no_match(/[O0IL1]/, code, "#{code} contains an ambiguous character")
        assert_match(/\A[BCDFGHJKMNPQRSTVWXYZ]+\z/, code)
      end
    end

    test 'a user code is displayed grouped and compared ungrouped' do
      assert_equal 'WDJB-MJHT', Platform::Oauth::DeviceCode.format_user_code('WDJBMJHT')

      # Everything a user might plausibly type for the same code.
      ['WDJB-MJHT', 'wdjb-mjht', 'WDJBMJHT', 'wdjbmjht', ' WDJB MJHT ', 'wdjb mjht'].each do |typed|
        assert_equal 'WDJBMJHT', Platform::Oauth::DeviceCode.normalize_user_code(typed),
                     "#{typed.inspect} should normalise to the same code"
      end
    end

    test 'an empty or punctuation-only code never matches a record' do
      app.create_device_code

      ['', '   ', '----', nil].each do |junk|
        assert_nil Platform::Oauth::DeviceCode.pending_for_user_code(junk),
                   "#{junk.inspect} should not find anything"
      end
    end

    ##########################################################################
    #### Lookup, and what must not be findable
    ##########################################################################

    test 'a pending code is found by its user code, however it is typed' do
      code = app.create_device_code

      found = Platform::Oauth::DeviceCode.pending_for_user_code(code.user_code_for_display.downcase)
      assert_equal code.id, found.id
    end

    test 'an expired code is not pending' do
      code = app.create_device_code
      # #update_attribute, not #update_attributes: the latter was removed in Rails 6.  It is also
      # what rails-3.2.x needs, where OauthToken declares attr_accessible and mass assignment
      # silently drops valid_to -- so one spelling works on every branch.
      code.update_attribute(:valid_to, 1.minute.ago)

      assert_nil Platform::Oauth::DeviceCode.pending_for_user_code(code.user_code)
    end

    test 'an invalidated code is not pending' do
      code = app.create_device_code
      code.invalidate!

      assert_nil Platform::Oauth::DeviceCode.pending_for_user_code(code.user_code)
    end

    # Single use.  Without this a code could be approved, exchanged, and then presented at the
    # verification page again to be re-approved for a second token.
    test 'an exchanged code is not pending' do
      code = app.create_device_code
      code.exchanged_at = Time.now
      code.save!

      assert_nil Platform::Oauth::DeviceCode.pending_for_user_code(code.user_code)
    end

    ##########################################################################
    #### The two codes on one row
    ##########################################################################

    test 'the device code is the token and the user code is the secret' do
      code = app.create_device_code

      assert_not_nil code.device_code
      assert_equal code.secret, code.user_code
      assert_not_equal code.device_code, code.user_code

      # The device_code is what the client polls with, so it has to be long.
      assert code.device_code.length >= 40, "device_code was only #{code.device_code.length} characters"
    end

    test 'a new code is pending, not authorized' do
      code = app.create_device_code

      assert_equal true,  code.pending?
      assert_equal false, !!code.authorized?
      assert_nil code.user_id, 'nobody has approved it yet, so there is no user on it'
    end

    test 'approving a code records who approved it and stops it being pending' do
      code = app.create_device_code
      code.user = user
      code.authorize!

      assert_equal true,  !!code.reload.authorized?
      assert_equal false, code.pending?
      assert_equal user.id, code.user_id
    end

    test 'the scope is narrowed when it is created, not when it is exchanged' do
      code = app.create_device_code('basic')
      assert_equal 'basic', code.scope
    end

  end # class DeviceCodeTest
end # module Platform
