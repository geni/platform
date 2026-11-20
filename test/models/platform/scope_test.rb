require 'test_helper'

module Platform
  class ScopeTest < Platform::TestCase

    test 'find_or_create is idempotent' do
      a = Platform::Scope.find_or_create('user_basic')
      b = Platform::Scope.find_or_create('user_basic')

      assert_equal a.id, b.id
      assert_equal 1, Platform::Scope.where(keyword: 'user_basic').count
    end

    test 'for returns nil for an unknown keyword' do
      assert_nil Platform::Scope.for('nothing_like_this')
    end

    test 'for finds a scope by keyword' do
      scope = Platform::Scope.find_or_create('user_basic')

      assert_equal scope.id, Platform::Scope.for('user_basic').id
    end

    # description is NOT NULL, and #find_or_create is called from Platform::Application#add_scope
    # and from the seeder with nothing but a keyword, so the empty default is what keeps those
    # from being a NOT NULL violation.
    test 'find_or_create supplies the NOT NULL description' do
      scope = Platform::Scope.find_or_create('user_basic')

      assert_equal 'user_basic', scope.keyword
      assert_equal '', scope.description
      assert scope.persisted?
    end

    test 'find_or_create does not overwrite an existing description' do
      Platform::Scope.find_or_create('user_basic').update!(description: 'Basic profile')

      assert_equal 'Basic profile', Platform::Scope.find_or_create('user_basic').description
    end

    ##########################################################################
    #### developer_options
    ####
    #### This used to be `where("level = 0")`, to keep the capability flags (level 1000) out of a
    #### list of things a developer may request.  Flags are not in this table any more, so there
    #### is nothing to exclude -- and the old filter silently hid any row whose level was NULL,
    #### which is what both production rows turned out to have.
    ##########################################################################

    test 'developer_options orders by position' do
      Platform::Scope.find_or_create('third').update!(position: 30)
      Platform::Scope.find_or_create('first').update!(position: 10)
      Platform::Scope.find_or_create('second').update!(position: 20)

      assert_equal %w[first second third], Platform::Scope.developer_options.map { |s| s.keyword.to_s }
    end

    test 'developer_options includes a scope whose position is NULL' do
      Platform::Scope.find_or_create('positioned').update!(position: 10)
      Platform::Scope.find_or_create('no_position')

      keywords = Platform::Scope.developer_options.map { |s| s.keyword.to_s }

      assert_includes keywords, 'positioned'
      assert_includes keywords, 'no_position'
    end

    test 'developer_options is empty when the catalogue is' do
      assert_equal [], Platform::Scope.developer_options.to_a
    end

    ##########################################################################
    #### icon_url
    ####
    #### Site media is disabled in this configuration, so this takes the branch that reads the
    #### association directly rather than going through Platform::Config.
    ##########################################################################

    test 'icon_url falls back to the default when no icon is stored' do
      assert_equal false, Platform::Config.site_media_enabled?
      assert_equal Platform::Config.default_app_icon, Platform::Scope.find_or_create('user_basic').icon_url
    end

    test 'icon_url reads the stored icon' do
      scope = Platform::Scope.find_or_create('user_basic')
      scope.update!(icon: Platform::Media::Image.create!(file_location: 'ab/cd', file_name: 'i.png'))

      assert_equal scope.icon.url, scope.icon_url
    end

    test 'the icon is optional' do
      assert_nil Platform::Scope.find_or_create('user_basic').icon
    end

    test 'icon_url delegates to the host application when site media is enabled' do
      scope = Platform::Scope.find_or_create('user_basic')
      scope.update!(icon: Platform::Media::Image.create!(file_location: 'ab/cd', file_name: 'i.png'))

      Platform::Config.stubs(:site_media_enabled?).returns(true)
      Platform::Config.stubs(:icon_url).with(scope.icon).returns('https://cdn.example.com/i.png')

      assert_equal 'https://cdn.example.com/i.png', scope.icon_url
    end

    test 'store_icon hands the file to the host application when site media is enabled' do
      scope = Platform::Scope.find_or_create('user_basic')
      icon  = Platform::Media::Image.create!(file_location: 'ab/cd', file_name: 'i.png')

      Platform::Config.stubs(:site_media_enabled?).returns(true)
      Platform::Config.stubs(:create_media).returns(icon)

      scope.store_icon(File.new(Rails.root.join('public', 'icon.png')))

      assert_equal icon.id, scope.reload.icon_id
    end

    # Without site media the gem resizes the file itself, through Platform::Media::Media#write.
    # See media_test.rb.
    test 'store_icon resizes the file itself without site media' do
      with_tmp_media_path do
        scope = Platform::Scope.find_or_create('user_basic')

        assert_equal false, Platform::Config.site_media_enabled?
        scope.store_icon(fixture_image)

        assert_not_nil scope.reload.icon
        assert File.exist?(scope.icon.local_path)
        assert_equal 16, Magick::ImageList.new(scope.icon.local_path).first.columns
      end
    end

    ##########################################################################
    #### Associations
    ##########################################################################

    test 'a scope knows the applications it has been granted to' do
      scope = Platform::Scope.find_or_create('user_email')
      app.add_scope('user_email')

      assert_equal 1, scope.reload.application_scopes.size
      assert_equal app.id, scope.application_scopes.first.application_id
    end

    ##########################################################################
    #### Seeding
    ##########################################################################

    # Two shapes are in use, because the host application replaces this file wholesale: the gem
    # ships a flat list of bare keywords, Geni ships groups with a nested "scopes" hash.  The old
    # seeder handled neither -- it passed each top-level value straight to update_attributes, so
    # against the flat file it called it with nil and against the nested one it tried to create a
    # scope named after the *group*.  That is why production never had this catalogue in it, only
    # the two rows somebody added by hand.
    test 'seeding accepts the flat shape the gem ships' do
      with_catalogue('user_basic' => nil, 'family_basic' => nil) do
        Platform::Config.init_default_scopes
      end

      assert_equal 1, Platform::Scope.where(keyword: 'user_basic').count
      assert_equal 1, Platform::Scope.where(keyword: 'family_basic').count
    end

    test 'seeding accepts the nested shape Geni ships, and assigns only real columns' do
      catalogue = {
        'user_scopes' => {
          'headline'    => 'My Profile Information',
          'description' => 'Profile of the currently logged in user',
          'scopes'      => {
            'user_email' => {
              'position'    => 20,
              'headline'    => 'Send me email',
              'description' => '{app} may email me directly',
              # presentation, not a column -- must not reach the assignment
              'default'     => true,
            },
          },
        },
      }

      with_catalogue(catalogue) { Platform::Config.init_default_scopes }

      scope = Platform::Scope.find_by_keyword('user_email')
      assert_not_nil scope, 'the scope under the group should have been created'
      assert_equal 20, scope.position
      assert_equal 'Send me email', scope.headline
      assert_equal '{app} may email me directly', scope.description
      # the group itself is not a scope
      assert_nil Platform::Scope.find_by_keyword('user_scopes')
    end

    test 'seeding is idempotent and does not violate the NOT NULL description' do
      with_catalogue('tree_basic' => nil) do
        Platform::Config.init_default_scopes
        Platform::Config.init_default_scopes
      end

      assert_equal 1, Platform::Scope.where(keyword: 'tree_basic').count
      assert_not_nil Platform::Scope.find_by_keyword('tree_basic').description
    end

private

    def with_catalogue(hash)
      original = Platform::Config.instance_variable_get(:@default_scopes)
      Platform::Config.instance_variable_set(:@default_scopes, hash)
      yield
    ensure
      Platform::Config.instance_variable_set(:@default_scopes, original)
    end

  end # class ScopeTest
end # module Platform
