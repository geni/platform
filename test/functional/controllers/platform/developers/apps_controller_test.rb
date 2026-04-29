require_relative '../../../../test_helper'

class Platform::Developer::AppsControllerTest < ActionController::TestCase

  test 'apps requires login' do
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'apps' do
    login_as user
    get :index
    assert_redirected_to '/platform/developer/registration'
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
      post :create, :application => {:name => 'TestApp', :url => 'http://localhost', :callback_url => 'http://localhost', :contact_email => 'dev@geni.com'}, :authenticity_token => form_authenticity_token
    end

    app = Platform::Application.first(:order => 'id desc')
    assert_redirected_to :action => :index, :id => app.id
    # Rails 3.0 uses @response.flash, Rails 3.1+ uses flash
    flash_accessor = defined?(Rails::VERSION) && Rails::VERSION::MAJOR == 3 && Rails::VERSION::MINOR >= 1 ? flash : @response.flash
    assert_match 'registered', flash_accessor[:trfn]
    assert_nil flash_accessor[:trfe]

    assert_equal 'TestApp', app.name
    assert_not_nil app.key
    assert_not_nil app.secret
  end

  test 'create failure' do
    login_as developer

    assert_no_difference 'Platform::Application.count' do
      post :create, :application => {:name => 'TestApp', :url => '\0'}, :authenticity_token => form_authenticity_token
      assert_response :success
    end

    # Rails 2.3 uses 'new.html.erb', Rails 3.0 uses 'platform/developer/apps/new'
    if defined?(PlatformGem::Application)
      assert_template 'platform/developer/apps/new'
    else
      assert_template 'new.html.erb'
    end
    # Rails 3.0 uses @response.flash, Rails 3.1+ uses flash
    flash_accessor = defined?(Rails::VERSION) && Rails::VERSION::MAJOR == 3 && Rails::VERSION::MINOR >= 1 ? flash : @response.flash
    assert_nil flash_accessor[:trfn]
    assert_match 'invalid', flash_accessor[:error]
  end

  test 'edit requires login' do
    get :edit
    assert_redirected_to Platform::Config.default_url
  end

  test 'edit' do
    login_as developer
    app = developer.applications.create!(:name => 'TestApp', :url => 'http://localhost', :callback_url => 'http://localhost', :contact_email => 'dev@geni.com')
    get :edit, :id => app.id
    assert_response :success
  end

  test 'update requires login' do
    put :update
    assert_redirected_to Platform::Config.default_url
  end

  test 'update' do
    login_as developer
    app = developer.applications.create!(:name => 'TestApp', :url => 'http://localhost', :callback_url => 'http://localhost', :contact_email => 'dev@geni.com')

    put :update, :id => app.id, :application => {:name => 'Updated'}, :authenticity_token => form_authenticity_token
    assert_redirected_to :controller => 'platform/developer/apps', :action => :index, :id => app.id

    app.reload
    assert_equal 'Updated', app.name, 'Name should have changed'
  end

  test 'delete requires login' do
    delete :delete
    assert_redirected_to Platform::Config.default_url
  end

  test 'delete' do
    login_as developer
    app = developer.applications.create!(:name => 'TestApp', :url => 'http://localhost', :callback_url => 'http://localhost', :contact_email => 'dev@geni.com')

    assert_difference 'Platform::Application.count', -1 do
      delete :delete, :id => app.id, :authenticity_token => form_authenticity_token
      assert_redirected_to :controller => 'platform/developer/apps', :action => :index
    end
  end

end