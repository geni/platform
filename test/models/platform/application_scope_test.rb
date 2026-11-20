require 'test_helper'

module Platform
  # The join carrying the OAuth scopes granted to an application.
  #
  # Capability flags are not here -- they are the comma-separated permissions column on
  # platform_applications.  The two used to share platform_permissions, which is what made
  # Platform::Application#granted_scope able to intersect a requested OAuth scope against
  # :allow_iframe.
  class ApplicationScopeTest < Platform::TestCase

    test 'a join row reaches its application and scope' do
      scope = Platform::Scope.find_or_create('user_email')
      row   = Platform::ApplicationScope.create!(application: app, scope: scope)

      assert_equal app.id,   row.reload.application.id
      assert_equal scope.id, row.scope.id
    end

    test 'granting a scope writes a row that both sides can see' do
      scope = Platform::Scope.find_or_create('user_email')
      app.add_scope('user_email')

      row = Platform::ApplicationScope.where(application_id: app.id).first

      assert_not_nil row
      assert_equal scope.id, row.scope_id
      assert_equal [row.id], app.reload.application_scopes.map(&:id)
      assert_equal [row.id], scope.reload.application_scopes.map(&:id)
    end

    test 'one scope can be granted to several applications' do
      Platform::Scope.find_or_create('user_email')
      other = create_app(name: 'Other')
      app.add_scope('user_email')
      other.add_scope('user_email')

      assert_equal %w[user_email], app.reload.scope_keywords
      assert_equal %w[user_email], other.reload.scope_keywords
      assert_equal 2, Platform::ApplicationScope.where(scope_id: Platform::Scope.for('user_email').id).count
    end

    test 'join rows are destroyed with their application, and the scope survives' do
      scope = Platform::Scope.find_or_create('user_email')
      app.add_scope('user_email')
      id = app.id

      app.destroy

      assert_equal 0, Platform::ApplicationScope.where(application_id: id).count
      assert_equal 1, Platform::Scope.where(id: scope.id).count,
                   'the scope catalogue entry is not an application dependent'
    end

  end # class ApplicationScopeTest
end # module Platform
