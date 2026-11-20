require 'test_helper'

module Platform
  # The join between an application and the developers who work on it, over and above the single
  # owning developer in platform_applications.developer_id.
  #
  # This model declared a bare `belongs_to :developer`, which Rails resolves to Platform::Developer
  # -- the *module*; the class is Platform::Developer::Developer.  Saving a row therefore raised
  # "The Developer model class ... is not an ActiveRecord::Base subclass", so nothing in the gem
  # could add a co-developer to an application and both #application_developers associations were
  # permanently empty.  Platform::Application has always spelled the same association correctly,
  # which is where the :class_name now on this model came from.
  class ApplicationDeveloperTest < Platform::TestCase

    test 'a join row reaches its application and developer' do
      row = Platform::ApplicationDeveloper.create!(application: app, developer: developer)

      assert_equal app.id,       row.reload.application.id
      assert_equal developer.id, row.developer.id
    end

    test 'the developer association resolves to the model, not the enclosing module' do
      reflection = Platform::ApplicationDeveloper.reflect_on_association(:developer)

      assert_equal 'Platform::Developer::Developer', reflection.class_name
      assert_equal Platform::Developer::Developer, reflection.klass
    end

    test 'both sides of the join can be read back from the association' do
      row = Platform::ApplicationDeveloper.create!(application: app, developer: developer)

      assert_equal [row.id], app.reload.application_developers.map(&:id)
      assert_equal [row.id], developer.reload.application_developers.map(&:id)
    end

    test 'an application can carry several developers' do
      second = developer(create_user('second developer'))
      Platform::ApplicationDeveloper.create!(application: app, developer: developer)
      Platform::ApplicationDeveloper.create!(application: app, developer: second)

      assert_equal [developer.id, second.id].sort,
                   app.reload.application_developers.map(&:developer_id).sort
    end

    test 'a developer can be attached to several applications' do
      other = create_app(name: 'Other')
      Platform::ApplicationDeveloper.create!(application: app,   developer: developer)
      Platform::ApplicationDeveloper.create!(application: other, developer: developer)

      assert_equal [app.id, other.id].sort,
                   developer.reload.application_developers.map(&:application_id).sort
    end

    test 'both sides are required' do
      assert_raise ActiveRecord::RecordInvalid do
        Platform::ApplicationDeveloper.create!(developer: developer)
      end

      assert_raise ActiveRecord::RecordInvalid do
        Platform::ApplicationDeveloper.create!(application: app)
      end
    end

    # The co-developer join is not the owning developer, and attaching one must not change who
    # owns the application -- #developed_by? reads platform_applications.developer_id.
    test 'the join does not change which developer owns the application' do
      second = developer(create_user('second developer'))
      Platform::ApplicationDeveloper.create!(application: app, developer: second)

      assert_equal developer.id, app.reload.developer.id
      assert_equal true,  app.developed_by?(developer)
      assert_equal false, app.developed_by?(second)
    end

    test 'join rows are destroyed with their application' do
      id = app.id
      Platform::ApplicationDeveloper.create!(application: app, developer: developer)

      app.destroy

      assert_equal 0, Platform::ApplicationDeveloper.where(application_id: id).count
    end

  end # class ApplicationDeveloperTest
end # module Platform
