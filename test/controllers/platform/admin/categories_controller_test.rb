require 'test_helper'

# The category tree behind the application directory, and the screens that put applications into
# it.
class Platform::Admin::CategoriesControllerTest < Platform::ControllerTestCase

  test 'index requires an admin' do
    login_as user
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index opens on the root category' do
    login_as admin_user
    games

    get :index
    assert_response :success
    assert_equal root, assigned(:category)
    assert_equal root, assigned(:root)
  end

  test 'index opens on the category asked for' do
    login_as admin_user

    get :index, params: {category_id: games.id}
    assert_response :success
    assert_equal games, assigned(:category)
  end

  test 'tree renders with no layout' do
    login_as admin_user
    games

    get :tree
    assert_response :success
    assert_equal root, assigned(:category)
  end

  test 'items lists a category\'s children and applications' do
    login_as admin_user
    puzzles = Platform::Category.create!(parent: games, keyword: 'puzzles', name: 'Puzzles')
    featured = app_in(games, featured: true)
    regular  = app_in(games, featured: false, name: 'Regular')

    get :items, params: {parent_id: games.id}
    assert_response :success
    assert_equal [puzzles], assigned(:children).to_a
    assert_equal [featured.application_categories.first], assigned(:featured_apps).to_a
    assert_equal [regular.application_categories.first],  assigned(:apps).to_a
    assert_no_match '<html', response.body
  end

  ##########################################################################
  #### lb_update_category / update_category
  ##########################################################################

  test 'lb_update_category offers a blank form under a parent' do
    login_as admin_user

    get :lb_update_category, params: {parent_id: games.id}
    assert_response :success
    assert assigned(:category).new_record?
    assert_equal games, assigned(:parent)
    assert_equal games.id, assigned(:category).parent_id
  end

  test 'lb_update_category offers an existing category for editing' do
    login_as admin_user

    get :lb_update_category, params: {parent_id: root.id, category_id: games.id}
    assert_response :success
    assert_equal games, assigned(:category)
    assert_select 'input#category_name[value=?]', 'Games'
  end

  test 'update_category creates a category' do
    login_as admin_user
    root

    assert_difference 'Platform::Category.count' do
      post :update_category, params: {category: {parent_id: root.id, name: 'Puzzles',
                                                 keyword: 'puzzles', position: 3},
                                      authenticity_token: form_authenticity_token}
    end

    created = Platform::Category.find_by_keyword('puzzles')
    assert_redirected_to action: :index, category_id: created.id
    assert_equal 'Puzzles', created.name
    assert_equal root.id,   created.parent_id
    assert_equal 3,         created.position
  end

  test 'update_category edits an existing category' do
    login_as admin_user
    games

    assert_no_difference 'Platform::Category.count' do
      post :update_category, params: {category: {id: games.id, parent_id: root.id,
                                                 name: 'Renamed', keyword: 'games'},
                                      authenticity_token: form_authenticity_token}
    end

    assert_redirected_to action: :index, category_id: games.id
    assert_equal 'Renamed', games.reload.name
  end

  # Nothing was created, so there is no category to send the admin back to.  This used to ask the
  # nil for its #id.
  test 'update_category creates nothing over GET' do
    login_as admin_user
    root

    assert_no_difference 'Platform::Category.count' do
      get :update_category, params: {category: {parent_id: root.id, name: 'Puzzles'}}
    end

    assert_redirected_to action: :index
  end

  ##########################################################################
  #### lb_update_application_category / update_application_category
  ##########################################################################

  test 'lb_update_application_category offers the membership for editing' do
    login_as admin_user
    placed = app_in(games)
    app_cat = placed.application_categories.first

    get :lb_update_application_category, params: {category_id: games.id, app_id: placed.id}
    assert_response :success
    assert_equal app_cat, assigned(:app_cat)
    assert_no_match '<html', response.body
  end

  test 'update_application_category saves the membership' do
    login_as admin_user
    app_cat = app_in(games).application_categories.first

    post :update_application_category, params: {application_category: {id: app_cat.id, featured: '1', position: 7},
                                                authenticity_token: form_authenticity_token}
    assert_redirected_to action: :index, category_id: games.id

    app_cat.reload
    assert app_cat.featured
    assert_equal 7, app_cat.position
  end

  # application_id and category_id are what the row *is*; rewriting them would move the membership
  # to a different application or category rather than editing this one.
  test 'update_application_category will not move the membership' do
    login_as admin_user
    app_cat = app_in(games).application_categories.first
    elsewhere = Platform::Category.create!(parent: root, keyword: 'business', name: 'Business')

    post :update_application_category, params: {application_category: {id: app_cat.id, position: 7,
                                                                       category_id: elsewhere.id},
                                                authenticity_token: form_authenticity_token}
    assert_redirected_to action: :index, category_id: games.id
    assert_equal games.id, app_cat.reload.category_id
  end

  test 'update_application_category saves nothing over GET' do
    login_as admin_user
    app_cat = app_in(games).application_categories.first

    get :update_application_category, params: {application_category: {id: app_cat.id, position: 7}}
    assert_redirected_to action: :index, category_id: games.id
    assert_nil app_cat.reload.position
  end

  ##########################################################################
  #### delete_category
  ##########################################################################

  test 'delete_category removes the category' do
    login_as admin_user
    games

    assert_difference 'Platform::Category.count', -1 do
      post :delete_category, params: {category_id: games.id,
                                      authenticity_token: form_authenticity_token}
    end

    assert_redirected_to action: :index
  end

  # The delete walks down the tree, so a category cannot be removed while leaving its children
  # orphaned -- and the memberships pointing at each one go with it.
  test 'delete_category removes the subtree and the memberships under it' do
    login_as admin_user
    puzzles = Platform::Category.create!(parent: games, keyword: 'puzzles', name: 'Puzzles')
    app_in(games)
    app_in(puzzles, name: 'In a subcategory')

    assert_difference 'Platform::Category.count', -2 do
      assert_difference 'Platform::ApplicationCategory.count', -2 do
        post :delete_category, params: {category_id: games.id,
                                        authenticity_token: form_authenticity_token}
      end
    end

    assert_redirected_to action: :index
  end

  test 'delete_category removes nothing over GET' do
    login_as admin_user
    games

    assert_no_difference 'Platform::Category.count' do
      get :delete_category, params: {category_id: games.id}
    end

    assert_redirected_to action: :index
  end

  ##########################################################################
  #### assign_category -- the checkbox tree on an application's admin page
  ##########################################################################

  test 'assign_category puts the application in the category' do
    login_as admin_user
    puzzles = Platform::Category.create!(parent: games, keyword: 'puzzles', name: 'Puzzles')

    post :assign_category, params: {app_id: app.id, category_id: puzzles.id, checked: 'true',
                                    authenticity_token: form_authenticity_token}
    assert_response :success
    assert_includes app.reload.categories, puzzles
  end

  # Ticking a subcategory has to tick its ancestors too, or the application is in a subcategory of
  # a category it is not in -- and the directory lists by category.  The root is left out: every
  # category is under it, so membership would mean nothing.
  test 'assign_category walks up to the ancestors but not the root' do
    login_as admin_user
    puzzles = Platform::Category.create!(parent: games, keyword: 'puzzles', name: 'Puzzles')

    post :assign_category, params: {app_id: app.id, category_id: puzzles.id, checked: 'true',
                                    authenticity_token: form_authenticity_token}

    categories = app.reload.categories
    assert_includes categories, puzzles
    assert_includes categories, games
    assert_not_includes categories, root
  end

  test 'assign_category takes the application out of the category' do
    login_as admin_user
    app.add_category(games)

    post :assign_category, params: {app_id: app.id, category_id: games.id, checked: 'false',
                                    authenticity_token: form_authenticity_token}
    assert_response :success
    assert_not_includes app.reload.categories, games
  end

  test 'assign_category changes nothing over GET' do
    login_as admin_user

    get :assign_category, params: {app_id: app.id, category_id: games.id, checked: 'true'}
    assert_response :success
    assert_empty app.reload.categories
  end

  ##########################################################################
  #### category_assigner / category_assigner_tree
  ##########################################################################

  test 'category_assigner renders with no layout' do
    login_as admin_user
    games

    get :category_assigner, params: {app_id: app.id}
    assert_response :success
    assert_equal app, assigned(:app)
    assert_no_match '<html', response.body
  end

  test 'category_assigner_tree starts at the root by default' do
    login_as admin_user
    games

    get :category_assigner_tree, params: {app_id: app.id}
    assert_response :success
    assert_equal 'root', assigned(:root_keyword)
    assert_equal root, assigned(:root)
  end

  test 'category_assigner_tree can start somewhere else' do
    login_as admin_user

    get :category_assigner_tree, params: {app_id: app.id, root_keyword: games.keyword}
    assert_response :success
    assert_equal games, assigned(:root)
  end

  ##########################################################################
  #### update_featured_flag
  ##########################################################################

  test 'update_featured_flag features an application in its category' do
    login_as admin_user
    app_cat = app_in(games, featured: false).application_categories.first

    post :update_featured_flag, params: {app_category_id: app_cat.id, checked: 'true',
                                         authenticity_token: form_authenticity_token}
    assert_response :success
    assert app_cat.reload.featured
  end

  test 'update_featured_flag unfeatures it again' do
    login_as admin_user
    app_cat = app_in(games, featured: true).application_categories.first

    post :update_featured_flag, params: {app_category_id: app_cat.id, checked: 'false',
                                         authenticity_token: form_authenticity_token}
    assert_response :success
    assert_not app_cat.reload.featured
  end

  test 'update_featured_flag changes nothing over GET' do
    login_as admin_user
    app_cat = app_in(games, featured: false).application_categories.first

    get :update_featured_flag, params: {app_category_id: app_cat.id, checked: 'true'}
    assert_response :success
    assert_not app_cat.reload.featured
  end

private

  def root
    @root ||= Platform::Category.root
  end

  def games
    @games ||= Platform::Category.create!(parent: root, keyword: 'games', name: 'Games',
                                          position: 1)
  end

  def app_in(category, featured: nil, name: 'Categorised App')
    placed = create_app(name: name)
    Platform::ApplicationCategory.create!(application: placed, category: category,
                                          featured: featured)
    placed
  end

end # class Platform::Admin::CategoriesControllerTest
