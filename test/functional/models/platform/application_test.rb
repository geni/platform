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

    ##########################################################################
    #### Capability flags -- the platform_applications.permissions column
    ##########################################################################

    # These three were readable by has_permission? but were missing from the grantable list, so
    # the only way to set them was a console -- which is why Geni had been adding rows to
    # platform_permissions to make them appear in the admin screen, putting capability flags in
    # what the gem meant as a scope catalogue.
    test 'the grantable capability flags include the ones Geni actually reads' do
      [:allow_iframe, :sendgrid_callback, :skip_exception_logging].each do |flag|
        assert Platform::Application.permissions.include?(flag),
               "#{flag} should be grantable from the admin screen"
      end
    end

    test 'no OAuth scope is offered as a capability flag' do
      %w[basic user_basic user_email family_basic tree_basic].each do |scope|
        assert !Platform::Application.permissions.include?(scope.to_sym),
               "#{scope} is a scope and must not be grantable as a capability flag"
      end
    end

    # allow_iframe is the flag with the most visible failure mode: Geni's prevent_clickjacking
    # deletes X-Frame-Options for an application that holds it, so losing it means the app can no
    # longer frame us.  It is read from the string column, which the scope work must not disturb.
    test 'allow_iframe round-trips through the permissions column' do
      assert_equal false, app.has_permission?(:allow_iframe)

      app.set_permission(:allow_iframe, true)
      app.save!

      assert_equal true,  app.reload.has_permission?(:allow_iframe)
      assert_equal true,  app.permissions.to_s.split(',').include?('allow_iframe')
      assert_equal false, app.has_permission?(:no_rate_limit), 'flags must not leak into each other'
    end

    ##########################################################################
    #### OAuth scopes -- platform_application_scopes
    ##########################################################################

    test 'scopes start empty and can be granted by keyword' do
      assert_equal [], app.scope_keywords
      assert_equal false, app.scope_granted?('user_email')

      Platform::Scope.find_or_create('user_email')
      app.add_scope('user_email')

      assert_equal ['user_email'], app.reload.scope_keywords
      assert_equal true, app.scope_granted?('user_email')
    end

    test 'granting the same scope twice does not duplicate it' do
      Platform::Scope.find_or_create('user_email')
      app.add_scope('user_email')
      app.add_scope('user_email')

      assert_equal ['user_email'], app.reload.scope_keywords
    end

    test 'add_scope ignores a keyword with no scope record' do
      app.add_scope('not_a_registered_scope')
      assert_equal [], app.reload.scope_keywords
    end

    ##########################################################################
    #### The two namespaces must not meet
    ##########################################################################

    # The whole point of the split.  Before it, #granted_scope intersected the requested scope
    # against the capability keywords, so an application holding allow_iframe would have had
    # 'basic' narrowed to '' while an application holding nothing kept working.
    test 'a capability flag is not a registered scope' do
      app.set_permission(:allow_iframe, true)
      app.save!

      assert_equal [], app.reload.registered_scopes
      assert_equal 'basic', app.granted_scope('basic'),
                   'holding allow_iframe must not narrow a basic scope request'
    end

    test 'registered_scopes stays empty while enable_scopes? is false' do
      Platform::Scope.find_or_create('user_email')
      app.add_scope('user_email')

      with_scopes_enabled(false) do
        assert_equal [], app.reload.registered_scopes
        assert_equal 'user_email,junk', app.granted_scope('user_email,junk'),
                     'with scopes disabled the request passes through unnarrowed'
      end
    end

    test 'registered_scopes reports the granted scopes once enable_scopes? is true' do
      %w[user_basic user_email].each { |k| Platform::Scope.find_or_create(k) }
      app.add_scope('user_basic')
      app.add_scope('user_email')

      with_scopes_enabled(true) do
        assert_equal %w[user_basic user_email], app.reload.registered_scopes.sort
      end
    end

    test 'granted_scope narrows to the intersection once scopes are enabled' do
      Platform::Scope.find_or_create('user_basic')
      app.add_scope('user_basic')

      with_scopes_enabled(true) do
        app.reload
        assert_equal 'user_basic', app.granted_scope('user_basic,user_email')
        assert_equal '',           app.granted_scope('user_email')
        assert_equal 'basic',      app.granted_scope(''), 'blank still defaults to basic'
      end
    end

    ##########################################################################
    #### The catalogue
    ##########################################################################

    # The OAUTH_WOULD_REJECT census line must not fire while the scope system is off, because the
    # condition it reports is then true of every application on every authorize.
    test 'granted_scope passes the request through untouched while enable_scopes? is false' do
      Platform::Scope.find_or_create('user_basic')
      app.add_scope('user_basic')
      app.reload

      with_scopes_enabled(false) do
        assert_equal false, app.scope_registration_known?,
                     'nothing is registered as far as the scope check is concerned'
        assert_equal 'user_basic,anything', app.granted_scope('user_basic,anything')
      end
    end

    test 'developer_options returns every scope, including ones with no position' do
      a = Platform::Scope.find_or_create('user_basic')
      a.update_attributes(:position => 10, :description => 'first')
      b = Platform::Scope.find_or_create('zz_no_position')

      keywords = Platform::Scope.developer_options.map { |s| s.keyword.to_s }

      assert keywords.include?('user_basic')
      assert keywords.include?('zz_no_position'),
             'the old "level = 0" filter hid rows whose level was NULL, which both production rows were'
    end

    ##########################################################################
    #### Issuing an access token
    ####
    #### #issue_access_token is what every OAuth grant calls.  It exists because
    #### #find_or_create_access_token hands back a *stored* token, which is the one thing standing
    #### between Platform::Oauth::AccessToken and being digested at rest -- a digest cannot be
    #### turned back into the value a client needs.
    ##########################################################################

    test 'issuing twice hands out two different tokens' do
      first  = app.issue_access_token(user)
      second = app.issue_access_token(user)

      assert first.id != second.id, 'each grant should mint its own token, not reuse a stored one'
      assert first.client_token != second.client_token
    end

    # The whole point: a freshly minted token still carries its cleartext, so the grant has
    # something to render even when the stored column is a digest.
    test 'an issued token carries a usable cleartext' do
      token = app.issue_access_token(user)

      assert !token.client_token.nil?
      assert !token.client_token.empty?
    end

    # Not a refactor if this is dropped.  Platform::ApplicationUser.touch creates the row recording
    # that this member uses this application, and #active_user_count, the monthly-users module and
    # the canvas flow's own ApplicationUser.for check all read it.
    test 'issuing records that the member uses the application' do
      assert_nil Platform::ApplicationUser.for(app, user), 'no usage recorded yet'

      app.issue_access_token(user)

      assert !Platform::ApplicationUser.for(app, user).nil?,
             'issuing a token has to record app usage, the way find_or_create_access_token did'
    end

    # The #destroy inside #find_or_create_access_token is the only code in this gem that deletes an
    # access token row, so #issue_access_token has to keep pruning or the table grows unbounded.
    test 'issuing prunes a revoked token' do
      dead = app.create_access_token(user)
      dead.invalidate!

      app.issue_access_token(user)

      assert_nil Platform::Oauth::AccessToken.find_by_id(dead.id), 'a revoked row should be pruned'
    end

    test 'issuing prunes an expired token' do
      dead = app.create_access_token(user)
      dead.expire_in!(-1.hour)

      app.issue_access_token(user)

      assert_nil Platform::Oauth::AccessToken.find_by_id(dead.id), 'an expired row should be pruned'
    end

    # The difference from #find_or_create_access_token, which destroys every token but the one it
    # reuses -- including a live token of another scope, since #valid_token?(scope) answers false
    # for a scope mismatch.  Nothing reuses any more, so there is no reason to collapse a member to
    # one credential, and a second client of theirs gets to keep its own.
    test 'issuing leaves a live token alone' do
      live  = app.create_access_token(user, 'other_scope')
      token = app.issue_access_token(user, 'basic')

      assert !Platform::Oauth::AccessToken.find_by_id(live.id).nil?,
             'a live token of another scope is somebody else\'s working credential'
      assert token.id != live.id
    end

private

    def with_scopes_enabled(value)
      original = Platform::Config.config[:enable_scopes]
      Platform::Config.config[:enable_scopes] = value
      yield
    ensure
      Platform::Config.config[:enable_scopes] = original
    end

  end # class ApplicationTest
end # module Platform
