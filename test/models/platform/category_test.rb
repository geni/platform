require 'test_helper'

module Platform
  class CategoryTest < Platform::TestCase

    test 'root creates the root category and then finds it' do
      first  = Platform::Category.root
      second = Platform::Category.root

      assert_equal first.id, second.id
      assert_equal 'root', first.keyword
      assert_equal 1, Platform::Category.where(keyword: 'root').count
    end

    test 'root? is true only for the root keyword' do
      assert_equal true,  Platform::Category.root.root?
      assert_equal false, Platform::Category.create!(keyword: 'games', name: 'Games').root?
    end

    test 'category_id_by_keyword returns the id, or nil for an unknown keyword' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')

      assert_equal cat.id, Platform::Category.category_id_by_keyword('games')
      assert_nil Platform::Category.category_id_by_keyword('no_such_category')
    end

    test 'full_name walks the tree from the root down' do
      root   = Platform::Category.root
      games  = Platform::Category.create!(parent: root,  keyword: 'games',   name: 'Games')
      puzzle = Platform::Category.create!(parent: games, keyword: 'puzzles', name: 'Puzzles')

      assert_equal 'Root', root.full_name
      assert_equal 'Root &raquo; Games &raquo; Puzzles', puzzle.full_name
    end

    ##########################################################################
    #### The featured / regular split
    ####
    #### The two finders have to partition the category's applications between them, and the
    #### reason #regular_application_categories carries an "is NULL" arm is that `featured` is a
    #### nullable boolean with no default -- a row created without the flag is NULL, not false,
    #### and SQL's `featured = false` does not match NULL.  Without that arm such a row would
    #### appear in neither list.
    ##########################################################################

    test 'featured_application_categories returns only the flagged rows, in position order' do
      cat   = Platform::Category.create!(keyword: 'games', name: 'Games')
      late  = Platform::ApplicationCategory.create!(application: create_app(name: 'Late'),
                                                    category: cat, featured: true, position: 2)
      early = Platform::ApplicationCategory.create!(application: create_app(name: 'Early'),
                                                    category: cat, featured: true, position: 1)
      Platform::ApplicationCategory.create!(application: create_app(name: 'Regular'),
                                            category: cat, featured: false, position: 0)

      assert_equal [early.id, late.id], cat.featured_application_categories.map(&:id)
    end

    test 'regular_application_categories covers both false and an unset featured flag' do
      cat     = Platform::Category.create!(keyword: 'games', name: 'Games')
      explicit = Platform::ApplicationCategory.create!(application: create_app(name: 'False'),
                                                       category: cat, featured: false, position: 1)
      unset    = Platform::ApplicationCategory.create!(application: create_app(name: 'Unset'),
                                                       category: cat, position: 2)
      Platform::ApplicationCategory.create!(application: create_app(name: 'Featured'),
                                            category: cat, featured: true, position: 0)

      assert_nil unset.featured, 'the flag is nullable with no default, which is the case under test'
      assert_equal [explicit.id, unset.id], cat.regular_application_categories.map(&:id)
    end

    test 'both finders are scoped to their own category' do
      mine   = Platform::Category.create!(keyword: 'mine',   name: 'Mine')
      theirs = Platform::Category.create!(keyword: 'theirs', name: 'Theirs')
      Platform::ApplicationCategory.create!(application: app, category: theirs, featured: true)
      Platform::ApplicationCategory.create!(application: app, category: theirs, featured: false)

      assert_equal [], mine.featured_application_categories.to_a
      assert_equal [], mine.regular_application_categories.to_a
    end

    ##########################################################################
    #### Associations
    ##########################################################################

    test 'applications comes through application_categories' do
      cat = Platform::Category.create!(keyword: 'games', name: 'Games')
      Platform::ApplicationCategory.create!(application: app, category: cat)

      assert_equal [app.id], cat.applications.map(&:id)
    end

  end # class CategoryTest
end # module Platform
