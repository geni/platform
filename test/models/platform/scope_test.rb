require 'test_helper'

module Platform
  class ScopeTest < Platform::TestCase

    test 'find_or_create is idempotent' do
      a = Platform::Scope.find_or_create('user_basic')
      b = Platform::Scope.find_or_create('user_basic')

      assert_equal a.id, b.id
      assert_equal 1, Platform::Scope.where(:keyword => 'user_basic').count
    end

    test 'for returns nil for an unknown keyword' do
      assert_nil Platform::Scope.for('nothing_like_this')
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

      assert_equal 1, Platform::Scope.where(:keyword => 'user_basic').count
      assert_equal 1, Platform::Scope.where(:keyword => 'family_basic').count
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

      assert_equal 1, Platform::Scope.where(:keyword => 'tree_basic').count
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
