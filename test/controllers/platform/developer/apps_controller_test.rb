require 'test_helper'

module Platform
  module Developer
    class AppsControllerTest < Platform::ControllerTestCase

      test 'apps requires login' do
        get :index
        assert_redirected_to Platform::Config.default_url
      end

      test 'apps' do
        login_as user
        get :index
        assert_redirected_to '/platform/developer/registration'
      end

      test 'index shows the developer\'s application' do
        login_as developer
        app

        get :index
        assert_response :success
        assert_equal app, assigned(:app)
        assert_equal [app], assigned(:apps).to_a
        assert_match app.name, response.body
      end

      test 'index shows the application asked for' do
        login_as developer
        app
        second = create_app(name: 'Second')

        get :index, params: {id: second.id}
        assert_response :success
        assert_equal second, assigned(:app)
      end

      # The :id is not a capability: another developer's application is dropped and the viewer's
      # own most recently updated one is shown instead.
      test 'index will not show another developer\'s application' do
        other_app = create_app(developer: developer(create_user('Other Developer')))
        login_as developer
        app

        get :index, params: {id: other_app.id}
        assert_response :success
        assert_equal app, assigned(:app)
      end

      test 'index with no applications at all' do
        login_as developer

        get :index
        assert_response :success
        assert_nil assigned(:app)
        assert_empty assigned(:apps).to_a
      end

      # The menu belongs to the application family rather than to the version being looked at, so
      # a child version shows its parent's menu.
      test 'index hangs the menu off the parent version' do
        login_as developer
        parent = app
        child  = create_app(name: 'Child')
        child.update!(parent_id: parent.id)

        get :index, params: {id: child.id}
        assert_equal child,  assigned(:app)
        assert_equal parent, assigned(:menu_app)
      end

      # Only top-level applications are listed; the versions under one are reached through it.
      test 'index lists only the top level applications' do
        login_as developer
        parent = app
        child  = create_app(name: 'Child')
        child.update!(parent_id: parent.id)

        get :index
        assert_equal [parent], assigned(:apps).to_a
      end

      test 'new requires login' do
        get :new
        assert_redirected_to Platform::Config.default_url
      end

      test 'new' do
        login_as developer
        get :new
        assert_response :success
      end

      test 'create requires login' do
        get :create
        assert_redirected_to Platform::Config.default_url
      end

      test 'create successful' do
        login_as developer

        assert_difference 'Platform::Application.count' do
          post :create, params: {application: {name: 'TestApp', url: 'http://localhost', callback_url: 'http://localhost', contact_email: 'dev@example.com'}, authenticity_token: form_authenticity_token}
        end

        app = Platform::Application.order('id desc').first
        assert_redirected_to action: :index, id: app.id
        assert_match 'registered', flash[:trfn]
        assert_nil flash[:trfe]

        assert_equal 'TestApp', app.name
        assert_not_nil app.key
        assert_not_nil app.secret
      end

      test 'create failure' do
        login_as developer

        assert_no_difference 'Platform::Application.count' do
          post :create, params: {application: {name: 'TestApp', url: '\0'}, authenticity_token: form_authenticity_token}
          assert_response :success
        end

        assert_match 'Register New Application', response.body
        assert_nil flash[:trfn]
        assert_match 'invalid', flash[:error]
      end

      test 'edit requires login' do
        get :edit
        assert_redirected_to Platform::Config.default_url
      end

      test 'edit' do
        login_as developer
        app = developer.applications.create!(name: 'TestApp', url: 'http://localhost', callback_url: 'http://localhost', contact_email: 'dev@example.com')
        get :edit, params: {id: app.id}
        assert_response :success
      end

      test 'update requires login' do
        put :update
        assert_redirected_to Platform::Config.default_url
      end

      test 'update' do
        login_as developer
        app = developer.applications.create!(name: 'TestApp', url: 'http://localhost', callback_url: 'http://localhost', contact_email: 'dev@example.com')

        put :update, params: {id: app.id, application: {name: 'Updated'}, authenticity_token: form_authenticity_token}
        assert_redirected_to controller: 'platform/developer/apps', action: :index, id: app.id

        app.reload
        assert_equal 'Updated', app.name, 'Name should have changed'
      end

      test 'delete requires login' do
        delete :delete
        assert_redirected_to Platform::Config.default_url
      end

      test 'delete' do
        login_as developer
        app = developer.applications.create!(name: 'TestApp', url: 'http://localhost', callback_url: 'http://localhost', contact_email: 'dev@example.com')

        assert_difference 'Platform::Application.count', -1 do
          delete :delete, params: {id: app.id, authenticity_token: form_authenticity_token}
          assert_redirected_to controller: 'platform/developer/apps', action: :index
        end
      end

      ######################################################################
      #### validate_application_developer
      ####
      #### The before_action in front of every action that names an :id.  Without it a developer
      #### could edit, version, re-secret, submit or delete any application on the site by id.
      ######################################################################

      test 'another developer\'s application cannot be edited' do
        other_app = create_app(developer: developer(create_user('Other Developer')))
        login_as developer

        get :edit, params: {id: other_app.id}
        assert_redirected_to action: :index
        assert_match 'not authorized', flash[:trfe]
      end

      test 'another developer\'s application cannot be deleted' do
        other_app = create_app(developer: developer(create_user('Other Developer')))
        login_as developer

        assert_no_difference 'Platform::Application.count' do
          delete :delete, params: {id: other_app.id, authenticity_token: form_authenticity_token}
        end

        assert_redirected_to action: :index
        assert_match 'not authorized', flash[:trfe]
      end

      test 'another developer\'s application cannot be updated' do
        other_app = create_app(developer: developer(create_user('Other Developer')))
        login_as developer

        put :update, params: {id: other_app.id, application: {name: 'Hijacked'},
                              authenticity_token: form_authenticity_token}
        assert_redirected_to action: :index
        assert_not_equal 'Hijacked', other_app.reload.name
      end

      test 'another developer\'s secret cannot be reset' do
        other_app = create_app(developer: developer(create_user('Other Developer')))
        secret = other_app.secret
        login_as developer

        post :reset_secret, params: {id: other_app.id, authenticity_token: form_authenticity_token}
        assert_redirected_to action: :index
        assert_equal secret, other_app.reload.secret
      end

      ######################################################################
      #### create
      ######################################################################

      test 'create stores an icon and a logo when they are given' do
        login_as developer

        with_tmp_media_path do
          post :create, params: {application: {name: 'TestApp', url: 'http://localhost',
                                               callback_url: 'http://localhost',
                                               contact_email: 'dev@example.com'},
                                 new_icon: uploaded_image, new_logo: uploaded_image,
                                 authenticity_token: form_authenticity_token}
        end

        created = Platform::Application.order('id desc').first
        assert_not_nil created.icon_id
        assert_not_nil created.logo_id
      end

      ######################################################################
      #### update
      ######################################################################

      test 'update replaces the application\'s scopes' do
        login_as developer
        Platform::Scope.find_or_create('user_basic')
        Platform::Scope.find_or_create('family_basic')
        app.add_scope('user_basic')

        put :update, params: {id: app.id, application: {name: app.name},
                              scopes: 'family_basic',
                              authenticity_token: form_authenticity_token}
        assert_redirected_to action: :index, id: app.id

        assert_equal ['family_basic'], app.reload.scope_keywords
      end

      test 'update with no scopes clears them' do
        login_as developer
        Platform::Scope.find_or_create('user_basic')
        app.add_scope('user_basic')

        put :update, params: {id: app.id, application: {name: app.name},
                              authenticity_token: form_authenticity_token}
        assert_empty app.reload.scope_keywords
      end

      test 'update re-renders the form when the application is invalid' do
        login_as developer

        put :update, params: {id: app.id, application: {url: '\0'},
                              authenticity_token: form_authenticity_token}
        assert_response :success
        assert_match 'invalid', flash[:error]
        assert_not_equal '\0', app.reload.url
      end

      # Not a put or post, or an unverified one: the action falls through to re-rendering the
      # edit form rather than saving.
      test 'update over GET renders the edit form' do
        login_as developer

        get :update, params: {id: app.id, application: {name: 'Updated'}}
        assert_response :success
        assert_not_equal 'Updated', app.reload.name
      end

      ######################################################################
      #### reset_secret
      ######################################################################

      test 'reset_secret rotates the secret' do
        login_as developer
        secret = app.secret

        post :reset_secret, params: {id: app.id, authenticity_token: form_authenticity_token}
        assert_redirected_to action: :index, id: app.id
        assert_match 'has been reset', flash[:trfn]

        assert_not_equal secret, app.reload.secret
        assert_equal 40, app.secret.length
      end

      test 'reset_secret does nothing over GET' do
        login_as developer
        secret = app.secret

        get :reset_secret, params: {id: app.id}
        assert_redirected_to action: :index, id: app.id
        assert_equal secret, app.reload.secret
      end

      ######################################################################
      #### submit
      ######################################################################

      test 'submit sends the application for review' do
        login_as developer

        post :submit, params: {id: app.id, authenticity_token: form_authenticity_token}
        assert_redirected_to action: :index, id: app.id
        assert_equal 'submitted', app.reload.state
      end

      test 'submit does nothing over GET' do
        login_as developer

        get :submit, params: {id: app.id}
        assert_redirected_to action: :index, id: app.id
        assert_equal 'new', app.reload.state
      end

      ######################################################################
      #### create_version / version
      ######################################################################

      test 'create_version offers a copy of the application to edit' do
        login_as developer

        get :create_version, params: {id: app.id}
        assert_response :success
        assert_equal app, assigned(:current_app)
        assert assigned(:app).new_record?
        assert_equal app.name, assigned(:app).name
      end

      test 'version creates the new version and retires the old one under it' do
        login_as developer
        old_app = app

        assert_difference 'Platform::Application.count' do
          post :version, params: {current_version_id: old_app.id,
                                  application: {name: 'TestApp', version: '2.0',
                                                url: 'http://localhost',
                                                callback_url: 'http://localhost',
                                                contact_email: 'dev@example.com'},
                                  authenticity_token: form_authenticity_token}
        end

        new_app = Platform::Application.order('id desc').first
        assert_redirected_to action: :index, id: new_app.id

        assert_equal '2.0', new_app.version
        assert_equal developer, new_app.developer
        assert_equal new_app.id, old_app.reload.parent_id
      end

      # The new version inherits the old one's artwork unless new artwork is uploaded with it.
      test 'version carries the icon and logo over' do
        login_as developer
        old_app = app
        with_tmp_media_path do
          old_app.store_icon(fixture_image)
          old_app.store_logo(fixture_image)
        end

        post :version, params: {current_version_id: old_app.id,
                                application: {name: 'TestApp', version: '2.0',
                                              url: 'http://localhost',
                                              callback_url: 'http://localhost',
                                              contact_email: 'dev@example.com'},
                                authenticity_token: form_authenticity_token}

        new_app = Platform::Application.order('id desc').first
        assert_equal old_app.reload.icon_id, new_app.icon_id
        assert_equal old_app.logo_id,        new_app.logo_id
      end

      # Versioning an application that already has versions moves them under the new one, so the
      # family stays one generation deep.
      test 'version re-parents the versions the old application had' do
        login_as developer
        old_app = app
        child   = create_app(name: 'Child')
        child.update!(parent_id: old_app.id)

        post :version, params: {current_version_id: old_app.id,
                                application: {name: 'TestApp', version: '2.0',
                                              url: 'http://localhost',
                                              callback_url: 'http://localhost',
                                              contact_email: 'dev@example.com'},
                                authenticity_token: form_authenticity_token}

        new_app = Platform::Application.order('id desc').first
        assert_equal new_app.id, child.reload.parent_id
        assert_equal new_app.id, old_app.reload.parent_id
      end

      ######################################################################
      #### lb_scopes -- the scope picker
      ######################################################################

      test 'update stores a new icon and logo when they are given' do
        login_as developer

        with_tmp_media_path do
          put :update, params: {id: app.id, application: {name: app.name},
                                new_icon: uploaded_image, new_logo: uploaded_image,
                                authenticity_token: form_authenticity_token}
        end

        app.reload
        assert_not_nil app.icon_id
        assert_not_nil app.logo_id
      end

      test 'lb_scopes offers every scope and ticks the ones the application holds' do
        login_as developer
        held    = Platform::Scope.find_or_create('user_basic')
        not_held = Platform::Scope.find_or_create('family_basic')
        app.add_scope('user_basic')

        get :lb_scopes, params: {id: app.id}
        assert_response :success
        assert_equal Platform::Scope.developer_options.to_a, assigned(:options).to_a
        assert_no_match '<html', response.body

        # @scopes holds Platform::Scope records, because the view asks @scopes.include?(option).
        # It used to hold the comma-separated capability-flag string, so no box ever rendered
        # ticked and opening the picker cleared every scope the application had.
        assert_equal [held], assigned(:scopes).to_a
        assert_not_includes assigned(:scopes).to_a, not_held
      end

    private

      # #store_icon writes the file itself, so it needs a real upload rather than the plain
      # filename a File argument turns into on the way through a controller test.
      def uploaded_image
        Rack::Test::UploadedFile.new(Rails.root.join('public', 'icon.png'), 'image/png')
      end

    end # class AppsControllerTest
  end # module Developer
end # module Platform