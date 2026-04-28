ActionController::Routing::Routes.draw do |map|

  map.connect '/platform/developer/apps/:id',
              :controller => 'platform/developer/apps', :action => 'delete',
              :conditions => {:method => :delete}

  map.connect '/platform/developer/apps/:id',
              :controller => 'platform/developer/apps', :action => 'update',
              :conditions => {:method => :put}

  [:apps, :home, :login, :oauth, :forum, :ratings].each do |ctrl|
    map.connect "/platform/#{ctrl}/:action", :controller => "platform/#{ctrl}"
  end

  [:apps, :blog, :dashboard, :forum, :help, :issues, :registration, :resources].each do |ctrl|
    map.connect "/platform/developer/#{ctrl}/:action", :controller => "platform/developer/#{ctrl}"
  end

  [:apps, :categories, :developers].each do |ctrl|
    map.connect "/platform/admin/#{ctrl}/:action", :controller => "platform/admin/#{ctrl}"
  end

  map.namespace :platform do |subdomain|
    subdomain.root :controller => 'home', :action => 'index'
    subdomain.namespace :developer do |subsubdomain|
      subsubdomain.root :controller => 'dashboard', :action => 'index'
    end
    subdomain.namespace :admin do |subsubdomain|
      subsubdomain.root :controller => 'apps', :action => 'index'
    end
  end

end

# Rails 3.0 routes (only loaded when Rails 3.0 is active)
if defined?(PlatformGem::Application)
  PlatformGem::Application.routes.draw do
    # Stub tr8n routes for Rails 3.0 compatibility
    namespace :tr8n do
      match 'home' => 'home#index', :via => [:get, :post]
    end

    # Platform routes
    delete '/platform/developer/apps/:id' => 'platform/developer/apps#delete'
    put '/platform/developer/apps/:id' => 'platform/developer/apps#update'

    [:apps, :home, :login, :oauth, :forum, :ratings].each do |ctrl|
      match "/platform/#{ctrl}/:action" => "platform/#{ctrl}#:action", :via => [:get, :post]
    end

    [:apps, :blog, :dashboard, :forum, :help, :issues, :registration, :resources].each do |ctrl|
      match "/platform/developer/#{ctrl}/:action" => "platform/developer/#{ctrl}#:action", :via => [:get, :post]
    end

    [:apps, :categories, :developers].each do |ctrl|
      match "/platform/admin/#{ctrl}/:action" => "platform/admin/#{ctrl}#:action", :via => [:get, :post]
    end

    namespace :platform do
      root :to => 'home#index'
      namespace :developer do
        root :to => 'dashboard#index'
      end
      namespace :admin do
        root :to => 'apps#index'
      end
    end
  end
end
