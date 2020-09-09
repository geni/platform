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
      post :create, :application => {:name => 'TestApp', :url => 'http://localhost', :callback_url => 'http://localhost', :contact_email => 'dev@geni.com'}
    end

    app = Platform::Application.first(:order => 'id desc')
    assert_redirected_to :action => :index, :id => app.id
    assert_match 'registered', @response.flash[:trfn]
    assert_nil @response.flash[:trfe]

    assert_equal 'TestApp', app.name
    assert_not_nil app.key
    assert_not_nil app.secret
  end

  test 'create failure' do
    login_as developer

    assert_no_difference 'Platform::Application.count' do
      post :create, :application => {:name => 'TestApp', :url => '\0'}
      assert_response :success
    end

    assert_template 'new.html.erb'
    assert_nil @response.flash[:trfn]
    assert_match 'invalid', @response.flash[:error]
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

    put :update, :id => app.id, :application => {:name => 'Updated'}
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
      delete :delete, :id => app.id
    assert_redirected_to :controller => 'platform/developer/apps', :action => :index
    end
  end

end
