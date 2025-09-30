Platform::Engine.routes.draw do
  # also mounts WillFilter::Engine at /will_filter
  mount Tr8n::Engine => '/tr8n'

  namespace :admin do
    root :to => 'apps#index'
  end # namespace :admin

  namespace :developer do
    get     '/apps'         => 'apps#index'
    get     '/apps/:id'     => 'apps#edit'
    delete  '/apps/:id'     => 'apps#delete'
    put     '/apps/:id'     => 'apps#update'
    post    '/apps/create'  => 'apps#create'
    delete  '/apps/delete'  => 'apps#delete'
    get     '/apps/edit'    => 'apps#edit'
    get     '/apps/new'     => 'apps#new'
    put     '/apps/update'  => 'apps#update'

    root :to => 'dashboard#index'
  end # namespace :developer

  get     '/apps'     => 'apps#index'
  get     '/apps/:id' => 'apps#view', :as => 'app'

  get     '/home'         => 'home#index'
  get     '/home/credits' => 'home#credits'
  get     '/home/license' => 'home#license'

  get     '/oauth/authorize'        => 'oauth#authorize'
  get     '/oauth/authorize_web'    => 'oauth#authorize_web'
  get     '/oauth/invalidate_token' => 'oauth#invalidate_token'
  get     '/oauth/request_token'    => 'oauth#request_token'
  get     '/oauth/validate_token'   => 'oauth#validate_token'

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
end # Platform::Engine.routes.draw
