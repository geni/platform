require 'test_helper'

# The public application directory and the per-application page.
class Platform::AppsControllerTest < Platform::ControllerTestCase

  test 'index requires login' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index' do
    login_as user
    category

    get :index
    assert_response :success
    assert_match 'Application Directory', response.body
  end

  # With the directory switched off there is nothing public to browse, so the only applications
  # worth showing a viewer are their own.
  test 'index redirects to the developer\'s own applications when the directory is disabled' do
    Platform::Config.stubs(:enable_app_directory?).returns(false)
    login_as user

    get :index
    assert_redirected_to controller: '/platform/developer/apps', action: 'index'
  end

  # /platform/common/_scripts loads platform.js and then calls initializePlatform() -- in a block
  # written `<% javascript_tag do %>`, which discards what the block captures.  So the script was
  # fetched and never initialised on every page that renders one of the three common headers,
  # which is every page in the gem outside the oauth templates.
  test 'index loads and initialises the platform javascript' do
    login_as user
    category

    get :index
    assert_match 'platform/javascripts/platform.js', response.body
    assert_match 'initializePlatform()', response.body
  end

  test 'index defaults to the first category under the root' do
    login_as user
    first = category('Games', 1)
    category('Business', 2)

    get :index
    assert_equal first, assigned(:category)
  end

  test 'index shows the category asked for' do
    login_as user
    category('Games', 1)
    business = category('Business', 2)

    get :index, params: {cat_id: business.id}
    assert_equal business, assigned(:category)
  end

  test 'index splits a category\'s applications into featured and regular' do
    login_as user
    games = category
    featured = approved_app_in(games, 'Featured App', true)
    regular  = approved_app_in(games, 'Regular App', false)

    get :index
    assert_response :success
    assert_equal [featured], assigned(:featured_apps).to_a
    assert_equal [regular],  assigned(:apps).to_a
    assert_match 'Featured App', response.body
    assert_match 'Regular App',  response.body
  end

  test 'index says so when a category has nothing in it' do
    login_as user
    category

    get :index
    assert_match 'no applications in this category', response.body
  end

  ##########################################################################
  #### index -- search
  ####
  #### This was will_paginate's Rails 2 :conditions signature, so searching the directory was an
  #### ArgumentError rather than a result list.
  ##########################################################################

  test 'index searches by name' do
    login_as user
    category
    create_app(name: 'Findable')
    create_app(name: 'Something else')

    get :index, params: {search: 'Findab'}
    assert_response :success
    assert_equal ['Findable'], assigned(:search_apps).collect(&:name)
  end

  test 'index searches by description' do
    login_as user
    category
    create_app(name: 'Thing', description: 'a findable description')

    get :index, params: {search: 'findable desc'}
    assert_equal ['Thing'], assigned(:search_apps).collect(&:name)
  end

  test 'index searching clears the category' do
    login_as user
    category

    get :index, params: {search: 'anything'}
    assert_nil assigned(:category)
    assert_empty assigned(:featured_apps)
    assert_empty assigned(:apps)
  end

  test 'index orders search results by name' do
    login_as user
    category
    create_app(name: 'Beta search')
    create_app(name: 'Alpha search')

    get :index, params: {search: 'search'}
    assert_equal ['Alpha search', 'Beta search'], assigned(:search_apps).collect(&:name)
  end

  test 'index paginates search results' do
    login_as user
    category
    3.times { |n| create_app(name: "Search #{n}") }

    get :index, params: {search: 'Search', per_page: 2}
    assert_equal 3, assigned(:search_apps).total_entries
  end

  ##########################################################################
  #### view
  ##########################################################################

  test 'view requires login' do
    get :view, params: {id: app.id}
    assert_redirected_to Platform::Config.default_url
  end

  test 'view' do
    login_as user

    get :view, params: {id: app.id}
    assert_response :success
    assert_match app.name, response.body
    assert_equal app, assigned(:app)
    assert_equal 'Info', assigned(:section)
  end

  test 'view on an application that does not exist' do
    login_as user

    assert_raises ActiveRecord::RecordNotFound do
      get :view, params: {id: 0}
    end
  end

  test 'view lists the application\'s reviews' do
    login_as user
    Platform::Rating.create!(object: app, user: user, value: 4, comment: 'A review')

    get :view, params: {id: app.id, sec: 'Reviews'}
    assert_response :success
    assert_match 'A review', response.body
    assert_equal 1, assigned(:ratings).size
  end

  # /platform/ratings/_new was written `<% form_tag do %>`, which discards what the block
  # captures -- so the reviews tab rendered with no way to leave a review.
  test 'view offers the review form' do
    login_as user

    get :view, params: {id: app.id, sec: 'Reviews'}
    assert_select 'form#app_rating_form' do
      assert_select 'input[name=rating_value]'
      assert_select 'textarea[name=rating_comment]'
    end
  end

  test 'view does not list another application\'s reviews' do
    login_as user
    other = create_app(name: 'Other')
    Platform::Rating.create!(object: other, user: user, value: 4, comment: 'Not this one')

    get :view, params: {id: app.id, sec: 'Reviews'}
    assert_empty assigned(:ratings)
  end

  test 'view lists the application\'s discussions' do
    login_as user
    discussion = create_topic

    get :view, params: {id: app.id, sec: 'Discussions'}
    assert_response :success
    assert_match 'A topic', response.body
    assert_equal [discussion], assigned(:topics).to_a
    assert_nil assigned(:topic)
  end

  # Both forum post forms were written `<% form_tag do %>` too, so the discussions tab rendered
  # with no way to start a topic and a topic rendered with no way to reply.
  test 'view offers the new topic form' do
    login_as user

    get :view, params: {id: app.id, sec: 'Discussions'}
    assert_select 'form#forum_topic_form' do
      assert_select 'input[name=topic]'
      assert_select 'textarea[name=message]'
    end
  end

  test 'view offers the reply form on a discussion' do
    login_as user
    discussion = create_topic

    get :view, params: {id: app.id, sec: 'Discussions', topic_id: discussion.id}
    assert_select 'form#forum_topic_form' do
      assert_select 'textarea[name=message]'
    end
  end

  test 'view does not list another application\'s discussions' do
    login_as user
    other = create_app(name: 'Other')
    Platform::ForumTopic.create!(user: user, subject: other, topic: 'Elsewhere')

    get :view, params: {id: app.id, sec: 'Discussions'}
    assert_empty assigned(:topics).to_a
  end

  test 'view shows one discussion and its messages' do
    login_as user
    discussion = create_topic
    Platform::ForumMessage.create!(topic: discussion, user: user, message: 'First post')

    get :view, params: {id: app.id, sec: 'Discussions', topic_id: discussion.id}
    assert_response :success
    assert_match 'First post', response.body
    assert_equal discussion, assigned(:topic)
    assert_equal 1, assigned(:messages).size
  end

  # view.html.erb branches on @topic, so a topic_id naming nothing falls back to the topic list
  # rather than failing.
  test 'view with a topic_id that names nothing' do
    login_as user

    get :view, params: {id: app.id, sec: 'Discussions', topic_id: 0}
    assert_response :success
    assert_nil assigned(:topic)
  end

  test 'view with last_page lands on the last page of messages' do
    login_as user
    discussion = create_topic
    3.times { |n| Platform::ForumMessage.create!(topic: discussion, user: user, message: "Post #{n}") }

    get :view, params: {id: app.id, sec: 'Discussions', topic_id: discussion.id,
                        last_page: true, per_page: 2}
    assert_response :success
    assert_equal 2, @controller.params[:page]
  end

  test 'view offers the new topic form in create mode' do
    login_as user

    get :view, params: {id: app.id, sec: 'Discussions', mode: 'create'}
    assert_response :success
  end

  ##########################################################################
  #### paginate_module -- the ajax reload of one list on #index
  ##########################################################################

  test 'paginate_module reloads the featured applications' do
    login_as user
    games = category
    approved_app_in(games, 'Featured App', true)

    get :paginate_module, params: {module: 'featured_apps', cat_id: games.id}
    assert_response :success
    assert_match 'Featured App', response.body
  end

  test 'paginate_module reloads the suggested applications' do
    login_as user
    games = category
    approved_app_in(games, 'Regular App', false)

    get :paginate_module, params: {module: 'suggested_apps', cat_id: games.id}
    assert_response :success
    assert_match 'Regular App', response.body
  end

  test 'paginate_module reloads the search results' do
    login_as user
    create_app(name: 'Findable')

    get :paginate_module, params: {module: 'searched_apps', search: 'Findab'}
    assert_response :success
    assert_match 'Findable', response.body
  end

  ##########################################################################
  #### The actions that are gone
  ####
  #### #method_missing and its canvas page, #xd, #featured_applications_module_content and
  #### #apps_page have all been removed -- see the note in the controller.  What is pinned here
  #### is why the canvas page could not have worked: the URL it was supposed to live at belongs
  #### to #view, and Rails would not have dispatched to #method_missing even if it had not.
  ##########################################################################

  # action_methods also carries the public helpers the Platform and host base controllers define,
  # so this names what should and should not be dispatchable rather than comparing the whole set.
  test 'the removed actions are no longer dispatchable' do
    actions = Platform::AppsController.action_methods

    %w[index view paginate_module].each do |kept|
      assert_includes actions, kept
    end

    %w[xd apps_page featured_applications_module_content method_missing].each do |gone|
      assert_not_includes actions, gone
    end
  end

  test 'a canvas url routes to view, with the canvas name as the id' do
    assert_equal({controller: 'platform/apps', action: 'view', id: 'mycanvas'},
                 Platform::Engine.routes.recognize_path('/apps/mycanvas', method: :get))
  end

  test 'a canvas name is not an action on this controller' do
    create_app(name: 'Canvas App', canvas_name: 'mycanvas')

    assert_not_includes Platform::AppsController.action_methods, 'mycanvas'
    assert_not @controller.respond_to?(:action_missing, true)
  end

  # The columns and the forms that write them are deliberately still here: what embedded
  # applications should look like is a separate decision from dropping code that never ran.
  test 'an application still carries its canvas settings' do
    canvas_app = create_app(name: 'Canvas App', canvas_name: 'mycanvas',
                            canvas_url: 'http://example.com/canvas')

    assert_equal 'mycanvas', canvas_app.reload.canvas_name
    assert_equal 'http://example.com/canvas', canvas_app.canvas_url
    assert_equal "#{Platform::Config.site_url}/platform/apps/mycanvas", canvas_app.app_url
  end

private

  def category(name = 'Games', position = 1)
    @categories ||= {}
    @categories[name] ||= Platform::Category.create!(parent: Platform::Category.root,
                                                     keyword: name.parameterize.underscore,
                                                     name: name, position: position)
  end

  # #featured_for_category and #regular_for_category both only answer approved applications.
  def approved_app_in(category, name, featured)
    app = create_app(name: name)
    app.approve!
    Platform::ApplicationCategory.create!(application: app, category: category,
                                          featured: featured)
    app
  end

  def create_topic
    Platform::ForumTopic.create!(user: user, subject: app, topic: 'A topic')
  end

end # class Platform::AppsControllerTest
