require 'test_helper'

# The admin's application screens: five will_filter lists, the state transitions, the capability
# flags, and the two lightbox editors.
class Platform::Admin::AppsControllerTest < Platform::ControllerTestCase

  ##########################################################################
  #### The lists
  ##########################################################################

  test 'index requires an admin' do
    login_as user
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index lists the applications' do
    app
    login_as admin_user

    get :index
    assert_response :success
    assert_includes assigned(:apps).results.to_a, app
    assert_match app.name, response.body
  end

  test 'tokens lists the access tokens' do
    token = Platform::Oauth::AccessToken.create!(user: user, application: app, token: 'foo')
    login_as admin_user

    get :tokens
    assert_response :success
    assert_includes assigned(:tokens).results.to_a, token
  end

  test 'users lists the application users' do
    app_user = Platform::ApplicationUser.find_or_create(app, user)
    login_as admin_user

    get :users
    assert_response :success
    assert_includes assigned(:users).results.to_a, app_user
  end

  test 'scopes lists the scope catalogue' do
    scope = Platform::Scope.find_or_create('user_basic')
    login_as admin_user

    get :scopes
    assert_response :success
    assert_includes assigned(:scopes).results.to_a, scope
    assert_match 'user_basic', response.body
  end

  test 'ratings lists the reviews' do
    rating = Platform::Rating.create!(object: app, user: user, value: 4)
    login_as admin_user

    get :ratings
    assert_response :success
    assert_includes assigned(:ratings).results.to_a, rating
  end

  ##########################################################################
  #### view
  ##########################################################################

  test 'view requires an admin' do
    login_as user
    get :view, params: {app_id: app.id}
    assert_redirected_to Platform::Config.default_url
  end

  test 'view' do
    login_as admin_user

    get :view, params: {app_id: app.id}
    assert_response :success
    assert_equal app, assigned(:app)
    assert_match app.name, response.body
    assert_match app.key,  response.body
  end

  test 'view on an application that does not exist' do
    login_as admin_user

    assert_raises ActiveRecord::RecordNotFound do
      get :view, params: {app_id: 0}
    end
  end

  ##########################################################################
  #### The state transitions
  ##########################################################################

  test 'approve requires an admin' do
    app.submit!
    login_as user

    post :approve, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
    assert_equal 'submitted', app.reload.state
  end

  test 'approve' do
    app.submit!
    login_as admin_user

    post :approve, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_redirected_to action: :view, app_id: app.id
    assert_equal 'approved', app.reload.state
  end

  # Approving a new version retires the ones it replaces, so only one version of an application is
  # live at a time.
  test 'approve deprecates the versions it replaces' do
    old_version = create_app(name: 'Old')
    old_version.approve!
    app.submit!
    old_version.update!(parent_id: app.id)
    login_as admin_user

    post :approve, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_equal 'approved',   app.reload.state
    assert_equal 'deprecated', old_version.reload.state
  end

  test 'reject' do
    app.submit!
    login_as admin_user

    post :reject, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_redirected_to action: :view, app_id: app.id
    assert_equal 'rejected', app.reload.state
  end

  test 'block' do
    app.approve!
    login_as admin_user

    post :block, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_redirected_to action: :view, app_id: app.id
    assert_equal 'blocked', app.reload.state
  end

  # Blocking an application has to take its other versions with it, or the developer just points
  # their users at the version that is still live.
  test 'block blocks the other versions too' do
    child = create_app(name: 'Child')
    child.approve!
    app.approve!
    child.update!(parent_id: app.id)
    login_as admin_user

    post :block, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_equal 'blocked', app.reload.state
    assert_equal 'blocked', child.reload.state
  end

  # Unblocking does not restore the application to live: the state machine sends it back to :new,
  # so it has to be approved again.
  test 'unblock' do
    app.approve!
    app.block!
    login_as admin_user

    post :unblock, params: {app_id: app.id, authenticity_token: form_authenticity_token}
    assert_redirected_to action: :view, app_id: app.id
    assert_equal 'new', app.reload.state
  end

  # None of the transitions may happen on a GET: a link or an image tag pointing at one of these
  # would be enough otherwise.
  test 'the state transitions do nothing over GET' do
    app.submit!
    login_as admin_user

    %i[approve reject block unblock].each do |action|
      get action, params: {app_id: app.id}
      assert_redirected_to action: :view, app_id: app.id
      assert_equal 'submitted', app.reload.state, "#{action} should not have run"
    end
  end

  ##########################################################################
  #### The capability flags
  ##########################################################################

  test 'set_permission grants a flag' do
    login_as admin_user

    post :set_permission, params: {app_id: app.id, perm: 'trusted',
                                   authenticity_token: form_authenticity_token}
    assert_redirected_to action: :view, app_id: app.id
    assert app.reload.has_permission?(:trusted)
  end

  test 'remove_permission takes a flag away' do
    app.set_permission(:trusted, true)
    app.save!
    login_as admin_user

    post :remove_permission, params: {app_id: app.id, perm: 'trusted',
                                      authenticity_token: form_authenticity_token}
    assert_redirected_to action: :view, app_id: app.id
    assert_not app.reload.has_permission?(:trusted)
  end

  test 'set_permission grants nothing over GET' do
    login_as admin_user

    get :set_permission, params: {app_id: app.id, perm: 'trusted'}
    assert_redirected_to action: :view, app_id: app.id
    assert_not app.reload.has_permission?(:trusted)
  end

  test 'a non-admin cannot grant a flag' do
    login_as user

    post :set_permission, params: {app_id: app.id, perm: 'trusted',
                                   authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
    assert_not app.reload.has_permission?(:trusted)
  end

  ##########################################################################
  #### lb_edit / update -- the application edit lightbox
  ##########################################################################

  test 'lb_edit renders the edit form with no layout' do
    login_as admin_user

    get :lb_edit, params: {app_id: app.id}
    assert_response :success
    assert_equal app, assigned(:app)
    assert_select 'input#app_name'
    assert_no_match '<html', response.body
  end

  test 'update saves the application' do
    login_as admin_user

    post :update, params: {app_id: app.id, source_url: source_url,
                           app: {name: 'Renamed', description: 'A description',
                                 canvas_name: 'renamed', auto_signin: '1'},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to source_url

    app.reload
    assert_equal 'Renamed',       app.name
    assert_equal 'A description', app.description
    assert_equal 'renamed',       app.canvas_name
    assert app.auto_signin
  end

  # key and secret are the application's OAuth credentials; they are generated on create and
  # rotated through #reset_secret!, not set from a form.
  test 'update will not rewrite the application credentials' do
    login_as admin_user
    key, secret = app.key, app.secret

    post :update, params: {app_id: app.id, source_url: source_url,
                           app: {name: 'Renamed', key: 'chosen-key', secret: 'chosen-secret'},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to source_url

    app.reload
    assert_equal 'Renamed', app.name
    assert_equal key,    app.key
    assert_equal secret, app.secret
  end

  test 'update saves nothing over GET' do
    login_as admin_user

    get :update, params: {app_id: app.id, source_url: source_url, app: {name: 'Renamed'}}
    assert_redirected_to source_url
    assert_not_equal 'Renamed', app.reload.name
  end

  test 'update on an application that does not exist' do
    login_as admin_user

    post :update, params: {app_id: 0, source_url: source_url, app: {name: 'Renamed'},
                           authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
  end

  ##########################################################################
  #### lb_scope / delete_scope -- the scope catalogue editor
  ##########################################################################

  test 'lb_scope offers a blank form for a new scope' do
    login_as admin_user

    get :lb_scope
    assert_response :success
    assert assigned(:scope).new_record?
    assert_no_match '<html', response.body
  end

  test 'lb_scope offers an existing scope for editing' do
    scope = Platform::Scope.find_or_create('user_basic')
    login_as admin_user

    get :lb_scope, params: {scope_id: scope.id}
    assert_response :success
    assert_equal scope, assigned(:scope)
    assert_select 'input#scope_keyword[value=?]', 'user_basic'
  end

  test 'lb_scope creates a scope' do
    login_as admin_user

    assert_difference 'Platform::Scope.count' do
      post :lb_scope, params: {source_url: source_url,
                               scope: {keyword: 'user_basic', description: 'Basic info',
                                       headline: 'Your basics', position: 10},
                               authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url

    scope = Platform::Scope.for('user_basic')
    assert_equal 'Basic info',  scope.description
    assert_equal 'Your basics', scope.headline
    assert_equal 10,            scope.position
  end

  test 'lb_scope updates a scope' do
    scope = Platform::Scope.find_or_create('user_basic')
    login_as admin_user

    assert_no_difference 'Platform::Scope.count' do
      post :lb_scope, params: {scope_id: scope.id, source_url: source_url,
                               scope: {keyword: 'user_basic', description: 'Changed'},
                               authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
    assert_equal 'Changed', scope.reload.description
  end

  test 'delete_scope removes a scope' do
    scope = Platform::Scope.find_or_create('user_basic')
    login_as admin_user

    assert_difference 'Platform::Scope.count', -1 do
      post :delete_scope, params: {scope_id: scope.id, source_url: source_url,
                                   authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
  end

  test 'delete_scope removes nothing over GET' do
    Platform::Scope.find_or_create('user_basic')
    login_as admin_user

    assert_no_difference 'Platform::Scope.count' do
      get :delete_scope, params: {scope_id: Platform::Scope.for('user_basic').id,
                                  source_url: source_url}
    end

    assert_redirected_to source_url
  end

  test 'delete_scope on a scope that does not exist' do
    login_as admin_user

    post :delete_scope, params: {scope_id: 0, source_url: source_url,
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
  end

private

  def source_url
    'http://test.host/platform/admin/apps'
  end

end # class Platform::Admin::AppsControllerTest
