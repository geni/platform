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
