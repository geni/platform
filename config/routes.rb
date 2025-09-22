Tr8n::Engine.routes.draw do
  mount WillFilter::Engine => '/will_filter'

  namespace :developer do
    delete  '/apps/:id' => 'platform/developer/apps#delete'
    put     '/apps/:id' => 'platform/developer/apps#update'
    root :to => 'dashboard#index'
  end # namespace :developer

  namespace :admin do
    root :to => 'apps#index'
  end # namespace :admin

  get '/', :to => 'home#index'

#  map.connect '/platform/developer/apps/:id',
#              :controller => 'platform/developer/apps', :action => 'delete',
#              :conditions => {:method => :delete}

#  map.connect '/platform/developer/apps/:id',
#              :controller => 'platform/developer/apps', :action => 'update',
#              :conditions => {:method => :put}

#  [:apps, :home, :login, :oauth, :forum, :ratings].each do |ctrl|
#    map.connect "/platform/#{ctrl}/:action", :controller => "platform/#{ctrl}"
#  end

#  [:apps, :blog, :dashboard, :forum, :help, :issues, :registration, :resources].each do |ctrl|
#    map.connect "/platform/developer/#{ctrl}/:action", :controller => "platform/developer/#{ctrl}"
#  end

#  [:apps, :categories, :developers].each do |ctrl|
#    map.connect "/platform/admin/#{ctrl}/:action", :controller => "platform/admin/#{ctrl}"
#  end

#  map.namespace :platform do |subdomain|
#    subdomain.root :controller => 'home', :action => 'index'
#    subdomain.namespace :developer do |subsubdomain|
#      subsubdomain.root :controller => 'dashboard', :action => 'index'
#    end
#    subdomain.namespace :admin do |subsubdomain|
#      subsubdomain.root :controller => 'apps', :action => 'index'
#    end
#  end
end # Tr8n::Engine.routes.draw
