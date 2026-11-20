require 'test_helper'

module Platform
  class ApplicationTest < Platform::TestCase

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

    test 'unlimited_models persists through the bang writer' do
      app.allow_unlimited_models!
      assert_equal true, app.reload.allow_unlimited_models?

      app.allow_unlimited_models!(false)
      assert_equal false, app.reload.allow_unlimited_models?
    end

    test 'grant_type_password persists through the bang writer' do
      app.allow_grant_type_password!
      assert_equal true, app.reload.allow_grant_type_password?

      app.allow_grant_type_password!(false)
      assert_equal false, app.reload.allow_grant_type_password?
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
      a.update(position: 10, description: 'first')
      b = Platform::Scope.find_or_create('zz_no_position')

      keywords = Platform::Scope.developer_options.map { |s| s.keyword.to_s }

      assert keywords.include?('user_basic')
      assert keywords.include?('zz_no_position'),
             'the old "level = 0" filter hid rows whose level was NULL, which both production rows were'
    end

    ##########################################################################
    #### The remaining capability flags
    ####
    #### Each is the same pair of methods over the permissions column.  The reason they are worth
    #### testing one by one rather than in a loop is #trusted, which was the odd one out: the
    #### negation in #rate_limited (whose permission is itself a negation, :no_rate_limit) had
    #### been copied to #trusted, where the permission is not negated, so #trusted! marked an
    #### application *un*trusted.  A loop over the flags would have passed either way.
    ##########################################################################

    test 'trusted is off by default and the writer turns it on' do
      assert_equal false, app.trusted?, 'applications are not trusted by default'

      app.trusted
      assert_equal true, app.trusted?, 'the writer must not negate -- :trusted is not a negation'

      app.trusted(false)
      assert_equal false, app.trusted?
    end

    # #trusted? is what skips the consent screen, so a writer that inverted it would silently
    # hand consent-free authorization to every application it was called on.
    test 'trusted! persists what trusted? reads back' do
      app.trusted!

      assert_equal true, app.reload.trusted?

      app.trusted!(false)
      assert_equal false, app.reload.trusted?
    end

    test 'public_client is off by default and round-trips' do
      assert_equal false, app.public_client?

      app.public_client!
      assert_equal true, app.reload.public_client?

      app.public_client!(false)
      assert_equal false, app.reload.public_client?
    end

    test 'tos_required is off by default and round-trips' do
      assert_equal false, app.tos_required?

      app.tos_required!
      assert_equal true, app.reload.tos_required?

      app.tos_required!(false)
      assert_equal false, app.reload.tos_required?
    end

    test 'add_without_premium is off by default and round-trips' do
      assert_equal false, app.allow_add_without_premium?

      app.allow_add_without_premium!
      assert_equal true, app.reload.allow_add_without_premium?

      app.allow_add_without_premium!(false)
      assert_equal false, app.reload.allow_add_without_premium?
    end

    test 'the bang writers persist and the plain writers do not' do
      app.rate_limited(false)
      assert_equal true, app.reload.rate_limited?, 'the plain writer leaves the change unsaved'

      app.rate_limited!(false)
      assert_equal false, app.reload.rate_limited?
    end

    test 'the client_credentials grant needs no flag' do
      assert_equal true, app.allow_grant_type_client_credentials?,
                   'every application may ask for a client token'
    end

    test 'the flags are independent of each other' do
      app.trusted!
      app.public_client!
      app.allow_grant_type_password!

      app.reload

      assert_equal true,  app.trusted?
      assert_equal true,  app.public_client?
      assert_equal true,  app.allow_grant_type_password?
      assert_equal false, app.tos_required?
      assert_equal false, app.allow_unlimited_models?
      assert_equal true,  app.rate_limited?
    end

    test 'clearing one flag leaves the others set' do
      app.trusted!
      app.public_client!

      app.trusted!(false)

      assert_equal false, app.reload.trusted?
      assert_equal true,  app.public_client?
    end

    test 'every grantable flag can actually be set and read back' do
      Platform::Application.permissions.each do |flag|
        app.set_permission(flag, true)
        assert_equal true, app.has_permission?(flag), "#{flag} should be settable"

        app.set_permission(flag, false)
        assert_equal false, app.has_permission?(flag), "#{flag} should be clearable"
      end
    end

    ##########################################################################
    #### Validations, keys and secrets
    ##########################################################################

    test 'a name is required' do
      a = Platform::Application.create(developer: developer)

      assert_equal false, a.persisted?
      assert_includes a.errors.full_messages, "Name can't be blank"
    end

    # The key and secret are generated before validation on create, which is what lets the
    # developer screens create an application without supplying either -- and why the
    # validates_presence_of on them never normally fires.
    test 'a key and secret are generated on create' do
      a = create_app

      assert_equal 40, a.key.length
      assert_equal 40, a.secret.length
      assert_match(/\A\w{40}\z/, a.key)
    end

    test 'the generated key is unique per application' do
      assert_not_equal create_app.key, create_app.key
    end

    test 'an explicit key and secret are kept' do
      a = create_app(key: 'my-own-key', secret: 'my-own-secret')

      assert_equal 'my-own-key',    a.key
      assert_equal 'my-own-secret', a.secret
    end

    test 'the key is unique across applications' do
      create_app(key: 'taken')
      a = Platform::Application.create(name: 'Dup', developer: developer, key: 'taken')

      assert_equal false, a.persisted?
      assert_includes a.errors.full_messages, 'Key has already been taken'
    end

    test 'reset_secret! replaces the secret and persists it' do
      a   = create_app
      was = a.secret

      a.reset_secret!

      assert_not_equal was, a.secret
      assert_equal 40, a.secret.length
      assert_equal a.secret, a.reload.secret
    end

    ##########################################################################
    #### URL validations
    ####
    #### All five are format-only and allow blank, so the thing worth pinning is that a value
    #### which is not a URL at all is refused on each of them -- these are the columns
    #### #registered_redirect_uris and #registered_origins are built from.
    ##########################################################################

    test 'each url column rejects a value that is not a url' do
      [:url, :support_url, :privacy_policy_url, :terms_of_service_url, :canvas_url].each do |column|
        a = Platform::Application.create(name: 'Bad', developer: developer, column => 'not a url')

        assert_equal false, a.persisted?, "#{column} should have been rejected"
        assert_equal 1, a.errors[column].size, "#{column} should carry the error"
      end
    end

    test 'each url column allows blank' do
      a = Platform::Application.create(name: 'Blank', developer: developer,
                                       url: '', support_url: nil,
                                       privacy_policy_url: '', terms_of_service_url: nil,
                                       canvas_url: '')

      assert_equal true, a.persisted?
    end

    test 'http and https urls are accepted' do
      assert create_app(url: 'http://example.com').persisted?
      assert create_app(url: 'https://example.com/path?x=1').persisted?
    end

    ##########################################################################
    #### self.for
    ####
    #### How the authorize and token endpoints turn a client_id into an application.  A client_id
    #### may be either the numeric id or the 40-character key.
    ##########################################################################

    test 'for finds an application by its numeric id' do
      assert_equal app.id, Platform::Application.for(app.id.to_s).id
    end

    test 'for finds an application by its key' do
      assert_equal app.id, Platform::Application.for(app.key).id
    end

    test 'for returns nil for a client_id that matches nothing' do
      assert_nil Platform::Application.for('no-such-client-id')
      assert_nil Platform::Application.for('999999999')
    end

    # #for calls String#match on its argument, so nil is a NoMethodError rather than nil.  The
    # callers all come from request parameters, where a missing client_id arrives as nil, so this
    # is worth knowing: the caller has to check before calling.
    test 'for raises on a nil client_id rather than returning nil' do
      assert_raise NoMethodError do
        Platform::Application.for(nil)
      end
    end

    ##########################################################################
    #### Display helpers
    ##########################################################################

    test 'short_description passes a short description through' do
      assert_equal 'Short', create_app(description: 'Short').short_description
    end

    test 'short_description is blank-safe' do
      assert_nil create_app(description: nil).short_description
      assert_equal '', create_app(description: '').short_description
    end

    test 'short_description truncates a long description with an ellipsis' do
      short = create_app(description: 'a' * 500).short_description

      assert_equal "#{'a' * 401}...", short
      assert_equal 404, short.length
    end

    test 'short_name passes a short name through' do
      assert_equal 'Short name', create_app(name: 'Short name').short_name
    end

    test 'short_name truncates a long name with an ellipsis' do
      assert_equal "#{'a' * 16}...", create_app(name: 'a' * 20).short_name
    end

    test 'versioned_name joins the name and version' do
      assert_equal 'TestApp 2.1', create_app(name: 'TestApp', version: '2.1').versioned_name
    end

    test 'category_names lists the category names' do
      games = Platform::Category.create!(keyword: 'games', name: 'Games')
      tools = Platform::Category.create!(keyword: 'tools', name: 'Tools')
      app.add_category('games')
      app.add_category('tools')

      assert_equal 'Games, Tools', app.reload.category_names
    end

    test 'category_names is blank with no categories' do
      assert_equal '', app.category_names
    end

    ##########################################################################
    #### The terms statement
    ##########################################################################

    test 'the default terms statement is blank when neither url is registered' do
      assert_equal '', create_app.default_terms_statement_tr_label
    end

    test 'the default terms statement names whichever urls are registered' do
      tos = create_app(terms_of_service_url: 'http://example.com/tos')
      assert_equal 'By proceeding, you agree to the {application} [link_tos: Terms of Service].',
                   tos.default_terms_statement_tr_label

      privacy = create_app(privacy_policy_url: 'http://example.com/privacy')
      assert_equal 'By proceeding, you agree to the {application} [link_privacy: Privacy Policy].',
                   privacy.default_terms_statement_tr_label
    end

    test 'the default terms statement joins both urls' do
      a = create_app(terms_of_service_url: 'http://example.com/tos',
                     privacy_policy_url: 'http://example.com/privacy')

      assert_equal 'By proceeding, you agree to the {application} ' \
                   '[link_tos: Terms of Service] and [link_privacy: Privacy Policy].',
                   a.default_terms_statement_tr_label
    end

    # tos_required? changes the wording from a notice to an acceptance, which is what turns the
    # consent screen's checkbox into a required one.
    test 'the wording becomes an acceptance when the terms must be accepted' do
      a = create_app(terms_of_service_url: 'http://example.com/tos')
      a.tos_required!

      assert_equal 'I accept the {application} [link_tos: Terms of Service].',
                   a.default_terms_statement_tr_label
    end

    test 'terms_statement_tr_label prefers an explicit consent label' do
      a = create_app(consent_label: 'Custom consent wording',
                     terms_of_service_url: 'http://example.com/tos')

      assert_equal 'Custom consent wording', a.terms_statement_tr_label
    end

    test 'terms_statement_tr_label falls back to the default for a nil or blank consent label' do
      a = create_app(consent_label: nil, terms_of_service_url: 'http://example.com/tos')
      assert_equal a.default_terms_statement_tr_label, a.terms_statement_tr_label

      b = create_app(consent_label: '   ', terms_of_service_url: 'http://example.com/tos')
      assert_equal b.default_terms_statement_tr_label, b.terms_statement_tr_label
    end

    ##########################################################################
    #### Authorizing and deauthorizing a user
    ##########################################################################

    test 'authorize_user records the user and authorized_user? reads it back' do
      assert_equal false, app.authorized_user?(user)

      app.authorize_user(user)

      assert_equal true, app.authorized_user?(user)
    end

    test 'authorized_user? is per user and per application' do
      app.authorize_user(user)

      assert_equal false, app.authorized_user?(create_user('someone else'))
      assert_equal false, create_app(name: 'Other').authorized_user?(user)
    end

    test 'authorize_user is idempotent' do
      app.authorize_user(user)
      app.authorize_user(user)

      assert_equal 1, Platform::ApplicationUser.where(application_id: app.id, user_id: user.id).count
    end

    test 'deauthorize_user forgets the user and invalidates their access tokens' do
      token = app.create_access_token(user, 'basic')
      app.authorize_user(user)

      app.deauthorize_user(user)

      assert_equal false, app.authorized_user?(user)
      assert_equal true,  token.reload.invalidated?
    end

    # #deauthorize_user goes through #invalidate_all_access_tokens, which reaches access tokens
    # only -- the user's refresh token survives a deauthorization and can still be exchanged for a
    # fresh access token.  OauthToken.revoke_all_for is what covers the whole family.
    test 'deauthorize_user does not reach the refresh token' do
      refresh = app.create_refresh_token(user, 'basic')
      app.authorize_user(user)

      app.deauthorize_user(user)

      assert_equal false, refresh.reload.invalidated?
      assert_equal true,  refresh.valid_token?
    end

    test 'deauthorizing a user who was never authorized is harmless' do
      app.deauthorize_user(user)

      assert_equal false, app.authorized_user?(user)
    end

    test 'authorize_user and authorized_user? default to the current user' do
      Platform::Config.init(user)

      app.authorize_user

      assert_equal true, app.authorized_user?
    ensure
      Platform::Config.reset!
    end

    ##########################################################################
    #### developed_by?
    ##########################################################################

    test 'developed_by? identifies the owning developer' do
      assert_equal true,  app.developed_by?(developer)
      assert_equal false, app.developed_by?(developer(create_user('someone else')))
    end

    test 'developed_by? defaults to the current developer' do
      Platform::Config.init(developer.user)
      assert_equal true, app.developed_by?

      Platform::Config.init(create_user('someone else'))
      assert_equal false, app.developed_by?
    ensure
      Platform::Config.reset!
    end

    ##########################################################################
    #### Categories
    ##########################################################################

    test 'add_category accepts a keyword or a record' do
      games = Platform::Category.create!(keyword: 'games', name: 'Games')
      tools = Platform::Category.create!(keyword: 'tools', name: 'Tools')

      app.add_category('games')
      app.add_category(tools)

      assert_equal %w[Games Tools], app.reload.categories.map(&:name).sort
    end

    test 'add_category is idempotent' do
      Platform::Category.create!(keyword: 'games', name: 'Games')
      app.add_category('games')
      app.add_category('games')

      assert_equal 1, app.reload.categories.size
    end

    test 'add_category ignores an unknown keyword' do
      assert_nil app.add_category('no_such_category')
      assert_equal [], app.reload.categories.to_a
    end

    test 'add_categories adds several at once' do
      Platform::Category.create!(keyword: 'games', name: 'Games')
      tools = Platform::Category.create!(keyword: 'tools', name: 'Tools')

      app.add_categories(['games', tools])

      assert_equal %w[Games Tools], app.reload.categories.map(&:name).sort
    end

    test 'remove_category accepts a keyword or a record' do
      games = Platform::Category.create!(keyword: 'games', name: 'Games')
      tools = Platform::Category.create!(keyword: 'tools', name: 'Tools')
      app.add_categories(%w[games tools])

      app.remove_category('games')
      assert_equal %w[Tools], app.reload.categories.map(&:name)

      app.remove_category(tools)
      assert_equal [], app.reload.categories.to_a
    end

    test 'remove_category ignores an unknown keyword and a category that was never added' do
      Platform::Category.create!(keyword: 'games', name: 'Games')

      assert_nil app.remove_category('no_such_category')
      assert_nil app.remove_category('games')
    end

    test 'remove_categories removes several at once' do
      Platform::Category.create!(keyword: 'games', name: 'Games')
      Platform::Category.create!(keyword: 'tools', name: 'Tools')
      app.add_categories(%w[games tools])

      app.remove_categories(%w[games tools])

      assert_equal [], app.reload.categories.to_a
    end

    ##########################################################################
    #### Metrics and reviews
    ##########################################################################

    test 'last_monthly_metric is the latest monthly rollup' do
      Platform::MonthlyApplicationMetric.find_or_create(app, Time.utc(2026, 1, 1))
      newest = Platform::MonthlyApplicationMetric.find_or_create(app, Time.utc(2026, 3, 1))
      Platform::MonthlyApplicationMetric.find_or_create(app, Time.utc(2026, 2, 1))

      assert_equal newest.id, app.last_monthly_metric.id
    end

    test 'last_total_metric is the latest total rollup' do
      Platform::TotalApplicationMetric.find_or_create(app, Time.utc(2026, 1, 1))
      newest = Platform::TotalApplicationMetric.find_or_create(app, Time.utc(2026, 3, 1))

      assert_equal newest.id, app.last_total_metric.id
    end

    # Both read through a type-scoped relation, so a rollup of another width must not be returned
    # as the answer -- all five metric classes share one table.
    test 'the metric accessors do not pick up another rollup width' do
      Platform::DailyApplicationMetric.find_or_create(app, Time.utc(2026, 6, 1))

      assert_nil app.last_monthly_metric
      assert_nil app.last_total_metric
    end

    test 'the metric accessors are scoped to the application' do
      Platform::MonthlyApplicationMetric.find_or_create(create_app(name: 'Other'), Time.utc(2026, 1, 1))

      assert_nil app.last_monthly_metric
    end

    test 'recently_updated_reviews lists at most five, newest first' do
      7.times do |i|
        Platform::Rating.create!(object: app, user: create_user("reviewer #{i}"),
                                 value: i, updated_at: i.days.ago)
      end

      reviews = app.recently_updated_reviews.to_a

      assert_equal 5, reviews.size
      assert_equal reviews.map(&:updated_at).sort.reverse, reviews.map(&:updated_at)
    end

    test 'recently_updated_reviews is scoped to the application' do
      Platform::Rating.create!(object: create_app(name: 'Other'), user: user, value: 5)

      assert_equal [], app.recently_updated_reviews.to_a
    end

    test 'recently_updated_discussions lists at most five, newest first' do
      7.times do |i|
        Platform::ForumTopic.create!(subject: app, user: user, topic: "topic #{i}",
                                     updated_at: i.days.ago)
      end

      topics = app.recently_updated_discussions.to_a

      assert_equal 5, topics.size
      assert_equal topics.map(&:updated_at).sort.reverse, topics.map(&:updated_at)
    end

    test 'recently_updated_discussions is scoped to the application' do
      Platform::ForumTopic.create!(subject: create_app(name: 'Other'), user: user, topic: 'theirs')

      assert_equal [], app.recently_updated_discussions.to_a
    end

    ##########################################################################
    #### Icons and logos
    ####
    #### Site media is disabled in this configuration, so these take the branch that reads the
    #### association directly rather than going through Platform::Config.
    ##########################################################################

    test 'icon_url and logo_url fall back to the defaults when none is stored' do
      assert_equal false, Platform::Config.site_media_enabled?
      assert_equal Platform::Config.default_app_icon, app.icon_url
      assert_equal Platform::Config.default_app_logo, app.logo_url
    end

    test 'icon_url and logo_url read the stored media' do
      app.update!(icon: Platform::Media::Image.create!(file_location: 'ab/cd', file_name: 'i.png'),
                  logo: Platform::Media::Image.create!(file_location: 'ef/01', file_name: 'l.png'))

      assert_equal app.icon.url, app.icon_url
      assert_equal app.logo.url, app.logo_url
    end

    # With site media enabled the gem hands the URL off to the host application rather than
    # reading Platform::Media::Image itself, which is the branch Geni runs on.
    test 'icon_url and logo_url delegate to the host application when site media is enabled' do
      app.update!(icon: Platform::Media::Image.create!(file_location: 'ab/cd', file_name: 'i.png'),
                  logo: Platform::Media::Image.create!(file_location: 'ef/01', file_name: 'l.png'))

      Platform::Config.stubs(:site_media_enabled?).returns(true)
      Platform::Config.stubs(:icon_url).with(app.icon).returns('https://cdn.example.com/i.png')
      Platform::Config.stubs(:logo_url).with(app.logo).returns('https://cdn.example.com/l.png')

      assert_equal 'https://cdn.example.com/i.png', app.icon_url
      assert_equal 'https://cdn.example.com/l.png', app.logo_url
    end

    test 'the defaults are used when nothing is stored, even with site media enabled' do
      Platform::Config.stubs(:site_media_enabled?).returns(true)

      assert_equal Platform::Config.default_app_icon, app.icon_url
      assert_equal Platform::Config.default_app_logo, app.logo_url
    end

    test 'store_icon and store_logo hand the file to the host application when site media is enabled' do
      icon = Platform::Media::Image.create!(file_location: 'ab/cd', file_name: 'i.png')
      logo = Platform::Media::Image.create!(file_location: 'ef/01', file_name: 'l.png')
      file = File.new(Rails.root.join('public', 'icon.png'))

      Platform::Config.stubs(:site_media_enabled?).returns(true)
      Platform::Config.stubs(:create_media).returns(icon).then.returns(logo)

      app.store_icon(file)
      app.store_logo(file)

      assert_equal icon.id, app.reload.icon_id
      assert_equal logo.id, app.logo_id
    end

    # With site media disabled the gem resizes the file itself, through
    # Platform::Media::Media#write.  See media_test.rb.
    test 'store_icon and store_logo resize the file themselves without site media' do
      with_tmp_media_path do
        assert_equal false, Platform::Config.site_media_enabled?

        app.store_icon(fixture_image)
        app.store_logo(fixture_image)

        assert_not_nil app.reload.icon
        assert_not_nil app.logo
        assert File.exist?(app.icon.local_path)
        assert File.exist?(app.logo.local_path)
      end
    end

    # 16 for the icon, 75 for the logo -- the two call sites differ only in that.
    test 'store_icon and store_logo resize to their own sizes' do
      with_tmp_media_path do
        app.store_icon(fixture_image)
        app.store_logo(fixture_image)

        assert_equal 16, Magick::ImageList.new(app.reload.icon.local_path).first.columns
        assert_equal 75, Magick::ImageList.new(app.logo.local_path).first.columns
      end
    end

    ##########################################################################
    #### oauth_url
    ##########################################################################

    test 'oauth_url names the application key and escapes the callback' do
      a   = create_app(callback_url: 'http://localhost/cb?x=1 2')
      url = a.oauth_url

      assert_includes url, "client_id=#{a.key}"
      assert_includes url, 'response_type=token'
      assert_includes url, 'display=web'
      assert_includes url, "redirect_url=#{CGI.escape('http://localhost/cb?x=1 2')}"
    end

    test 'oauth_url is https outside development' do
      assert_match(/\Ahttps:/, create_app.oauth_url)

      Platform::Config.stubs(:env).returns('development')
      assert_match(/\Ahttp:/, create_app(name: 'Dev').oauth_url)
    end

    test 'oauth_url copes with no registered callback' do
      assert_includes create_app(callback_url: nil).oauth_url, 'redirect_url='
    end

    ##########################################################################
    #### Associations and dependent destruction
    ##########################################################################

    test 'an application is a tree, ordered by version' do
      parent = create_app(name: 'Parent', version: '1')
      two    = create_app(name: 'Child', parent: parent, version: '2')
      one    = create_app(name: 'Child', parent: parent, version: '1.5')

      assert_equal [one.id, two.id], parent.children.map(&:id)
      assert_equal parent.id, two.parent.id
    end

    test 'destroying an application takes its dependents with it' do
      a  = create_app
      id = a.id
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')
      a.add_category('games')
      Platform::Scope.find_or_create('user_email')
      a.add_scope('user_email')
      a.create_access_token(user, 'basic')
      a.authorize_user(user)
      Platform::ApplicationLog.create!(application: a, user: user, event: 'x')
      Platform::ApplicationMetric.find_or_create(a, Time.utc(2026, 1, 1))
      Platform::ApplicationDeveloper.create!(application: a, developer: developer)

      a.destroy

      assert_equal 0, Platform::ApplicationCategory.where(application_id: id).count
      assert_equal 0, Platform::ApplicationScope.where(application_id: id).count
      assert_equal 0, Platform::Oauth::OauthToken.where(application_id: id).count
      assert_equal 0, Platform::ApplicationUser.where(application_id: id).count
      assert_equal 0, Platform::ApplicationLog.where(application_id: id).count
      assert_equal 0, Platform::ApplicationMetric.where(application_id: id).count
      assert_equal 0, Platform::ApplicationDeveloper.where(application_id: id).count
      assert_equal 1, Platform::Category.where(id: cat.id).count, 'the category itself survives'
    end

    test 'requires_signature? is false' do
      assert_equal false, app.requires_signature?
    end

    ##########################################################################
    #### Ratings and rank
    ####
    #### #rating_count and #rating_sum called count/sum with the Rails 2 :conditions signature,
    #### which raises ArgumentError -- so #update_rank!, their only caller, was unreachable and
    #### the rank column was never written.  platform_app_rank_tag reads `app.rank || 0`, so every
    #### application in the directory rendered at nought stars.
    ##########################################################################

    test 'rating_count, rating_sum and update_rank! summarise the ratings' do
      Platform::Rating.create!(object: app, user: user, value: 4)
      Platform::Rating.create!(object: app, user: create_user('second'), value: 2)

      assert_equal 2, app.rating_count
      assert_equal 6, app.rating_sum
      assert_equal 3, app.update_rank!
      assert_equal 3, app.reload.rank
    end

    test 'an application with no ratings ranks zero rather than dividing by zero' do
      assert_equal 0, app.rating_count
      assert_equal 0, app.rating_sum
      assert_equal 0, app.update_rank!
      assert_equal 0, app.reload.rank
    end

    test 'the rank is an integer average, truncated' do
      [5, 4, 4].each_with_index do |value, i|
        Platform::Rating.create!(object: app, user: create_user("reviewer #{i}"), value: value)
      end

      assert_equal 13, app.rating_sum
      assert_equal 4,  app.update_rank!, '13 / 3 truncates to 4'
    end

    test 'the ratings are scoped to the application' do
      Platform::Rating.create!(object: create_app(name: 'Other'), user: user, value: 5)

      assert_equal 0, app.rating_count
      assert_equal 0, app.rating_sum
    end

    # A rating row with no value must not be counted as a zero score, which would drag the
    # average down -- SQL SUM skips NULLs, but COUNT(*) does not.
    test 'a rating with no value contributes nothing to the sum' do
      Platform::Rating.create!(object: app, user: user, value: nil)

      assert_equal 1, app.rating_count
      assert_equal 0, app.rating_sum
    end

    test 'rating_count and rating_sum are memoized' do
      Platform::Rating.create!(object: app, user: user, value: 4)
      assert_equal 1, app.rating_count
      assert_equal 4, app.rating_sum

      Platform::Rating.create!(object: app, user: create_user('second'), value: 2)

      assert_equal 1, app.rating_count, 'memoized until the application is reloaded'
      assert_equal 4, app.rating_sum
    end

    ##########################################################################
    #### Site links
    ####
    #### Both of these interpolated a bare constant the gem never defined -- DEFAULT_SITE_LINK and
    #### SITE, which came from the host application's own top-level namespace -- so both raised
    #### NameError on any host that did not happen to have one.  They read
    #### Platform::Config.site_url now; see config_test.rb for that.
    ##########################################################################

    test 'admin_link points at the admin screen for this application' do
      assert_equal "#{Platform::Config.site_url}/admin/applications/view/#{app.id}", app.admin_link
      assert_match(%r{\Ahttps://}, app.admin_link)
    end

    test 'admin_link follows the configured host' do
      Platform::Config.stubs(:site_host).returns('admin.example.com')

      assert_equal "https://admin.example.com/admin/applications/view/#{app.id}", app.admin_link
    end

    # Only the canvas_name branch reached SITE, so this half of the method has always worked.
    test 'app_url returns the application url when there is no canvas name' do
      assert_equal 'http://localhost', create_app(canvas_name: nil).app_url
      assert_equal 'http://localhost', create_app(canvas_name: '').app_url
    end

    test 'app_url points at the canvas page for an embedded application' do
      a = create_app(canvas_name: 'mycanvas')

      assert_equal "#{Platform::Config.site_url}/platform/apps/mycanvas", a.app_url
    end

    # It used to hardcode http on this branch.  Going through #site_url means a canvas URL is
    # https outside development, like every other link the gem builds.
    test 'app_url is https outside development' do
      a = create_app(canvas_name: 'mycanvas')
      assert_match(%r{\Ahttps://}, a.app_url)

      Platform::Config.stubs(:env).returns('development')
      assert_match(%r{\Ahttp://}, a.app_url)
    end

    ##########################################################################
    #### The category finders
    ####
    #### These called #paginate with the Rails 2 :conditions / :joins / :order option hash, which
    #### will_paginate rejects with ArgumentError, so neither had a working call path and no
    #### category page in the application directory could list anything.
    ##########################################################################

    test 'featured_for_category and regular_for_category partition the category' do
      cat      = Platform::Category.create!(keyword: 'games', name: 'Games')
      featured = categorized(cat, 'Featured', featured: true)
      regular  = categorized(cat, 'Regular',  featured: false)

      assert_equal [featured.id], Platform::Application.featured_for_category(cat).map(&:id)
      assert_equal [regular.id],  Platform::Application.regular_for_category(cat).map(&:id)
    end

    # featured is a nullable boolean with no default, so a row created without the flag is NULL
    # and `featured = false` would not match it -- it has to show up as regular, or it is in
    # neither list and the application vanishes from the directory.
    test 'an application with no featured flag is regular' do
      cat   = Platform::Category.create!(keyword: 'games', name: 'Games')
      unset = categorized(cat, 'Unset')

      assert_equal [unset.id], Platform::Application.regular_for_category(cat).map(&:id)
      assert_equal [],         Platform::Application.featured_for_category(cat).to_a
    end

    test 'only approved applications are listed' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')
      %w[new submitted rejected blocked].each_with_index do |state, i|
        a = create_app(name: "App #{i}")
        a.submit!   if %w[submitted rejected].include?(state)
        a.reject!   if state == 'rejected'
        a.block!    if state == 'blocked'
        assert_equal state, a.reload.state
        Platform::ApplicationCategory.create!(application: a, category: cat, featured: true)
      end

      assert_equal [], Platform::Application.featured_for_category(cat).to_a
    end

    test 'the listings are ordered by the position the category gives them' do
      cat  = Platform::Category.create!(keyword: 'games', name: 'Games')
      last = categorized(cat, 'Last',  featured: true, position: 3)
      mid  = categorized(cat, 'Mid',   featured: true, position: 2)
      first = categorized(cat, 'First', featured: true, position: 1)

      assert_equal [first.id, mid.id, last.id],
                   Platform::Application.featured_for_category(cat).map(&:id)
    end

    test 'the listings are scoped to their category' do
      mine   = Platform::Category.create!(keyword: 'mine',   name: 'Mine')
      theirs = Platform::Category.create!(keyword: 'theirs', name: 'Theirs')
      categorized(theirs, 'Theirs', featured: true)

      assert_equal [], Platform::Application.featured_for_category(mine).to_a
      assert_equal [], Platform::Application.regular_for_category(mine).to_a
    end

    test 'the listings page' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')
      ids = (1..5).map { |i| categorized(cat, "App #{i}", featured: true, position: i).id }

      assert_equal ids[0, 2], Platform::Application.featured_for_category(cat, 1, 2).map(&:id)
      assert_equal ids[2, 2], Platform::Application.featured_for_category(cat, 2, 2).map(&:id)
      assert_equal ids[4, 1], Platform::Application.featured_for_category(cat, 3, 2).map(&:id)
    end

    # app/views/platform/apps/_paginator.html.erb reads these four off whatever comes back, so a
    # plain relation would not do.
    test 'the listings answer the paginator partial' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')
      3.times { |i| categorized(cat, "App #{i}", featured: true, position: i) }

      listing = Platform::Application.featured_for_category(cat, 1, 2)

      assert_equal 1, listing.current_page
      assert_equal 2, listing.total_pages
      assert_nil      listing.previous_page
      assert_equal 2, listing.next_page
      assert_equal 3, listing.total_entries
    end

    test 'the category finders return an empty list for a nil category' do
      assert_equal [], Platform::Application.featured_for_category(nil)
      assert_equal [], Platform::Application.regular_for_category(nil)
    end

    test 'the category finders return nothing for an empty category' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')

      assert_equal [], Platform::Application.featured_for_category(cat).to_a
      assert_equal [], Platform::Application.regular_for_category(cat).to_a
    end

private

    # An approved application placed in a category.  Approved because that is all the directory
    # lists, so an un-approved one would make every assertion here vacuous.
    def categorized(category, name, attrs = {})
      a = create_app(name: name)
      a.approve!
      Platform::ApplicationCategory.create!(attrs.merge(application: a, category: category))
      a
    end

    def with_scopes_enabled(value)
      original = Platform::Config.config[:enable_scopes]
      Platform::Config.config[:enable_scopes] = value
      yield
    ensure
      Platform::Config.config[:enable_scopes] = original
    end


    ##########################################################################
    #### Serialization
    ####
    #### Platform::Api::AppsController#index serializes every application to whoever asked, so
    #### what an application is willing to serialize is a security boundary rather than a
    #### presentation detail.
    ##########################################################################

    test 'the client secret is never serialized' do
      assert_not_includes app.serializable_hash.keys, 'secret'
      assert_no_match app.secret, app.to_json
      assert_no_match app.secret, app.to_xml
    end

    # The public client_id: a client sends it in the clear on every authorize request, so there is
    # nothing to protect (RFC 6749 section 2.2).
    test 'the client_id is serialized' do
      assert_equal app.key, app.serializable_hash['key']
    end

    test 'an explicit :except still applies on top' do
      hash = app.serializable_hash(except: [:name])

      assert_not_includes hash.keys, 'name'
      assert_not_includes hash.keys, 'secret'
      assert_includes hash.keys, 'key'
    end

    # ActiveModel lets :only win over :except -- it intersects and never consults :except -- so
    # filtering only :except would have left `only: [:secret]` asking for exactly the attribute
    # being withheld.
    test 'an explicit :only cannot ask for the secret' do
      assert_not_includes app.serializable_hash(only: [:secret]).keys, 'secret'
      assert_empty app.serializable_hash(only: [:secret])
    end

    test 'an explicit :only still narrows to what it may have' do
      assert_equal %w[key name], app.serializable_hash(only: [:key, :name, :secret]).keys.sort
    end

    # The screens that are entitled to show it read the attribute, not the serialization.
    test 'the secret is still readable as an attribute' do
      assert_equal 40, app.secret.length
    end

  end # class ApplicationTest
end # module Platform
