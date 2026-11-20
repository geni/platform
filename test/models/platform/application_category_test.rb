require 'test_helper'

module Platform
  class ApplicationCategoryTest < Platform::TestCase

    test 'find_or_create creates the join row once' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')

      first  = Platform::ApplicationCategory.find_or_create(app, cat)
      second = Platform::ApplicationCategory.find_or_create(app, cat)

      assert_equal first.id, second.id
      assert_equal 1, Platform::ApplicationCategory.where(application_id: app.id, category_id: cat.id).count
    end

    test 'find_or_create keys on both sides of the join' do
      games  = Platform::Category.create!(keyword: 'games',  name: 'Games')
      tools  = Platform::Category.create!(keyword: 'tools',  name: 'Tools')
      other  = create_app(name: 'Other')

      a = Platform::ApplicationCategory.find_or_create(app,   games)
      b = Platform::ApplicationCategory.find_or_create(app,   tools)
      c = Platform::ApplicationCategory.find_or_create(other, games)

      assert_equal 3, [a.id, b.id, c.id].uniq.size, 'each application/category pair is its own row'
    end

    test 'the join row reaches both sides' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')
      row = Platform::ApplicationCategory.find_or_create(app, cat)

      assert_equal app.id, row.application.id
      assert_equal cat.id, row.category.id
    end

  end # class ApplicationCategoryTest
end # module Platform
