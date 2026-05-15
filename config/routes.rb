Platform::Engine.routes.draw do
  # Stub tr8n routes for compatibility
  namespace :tr8n do
    match 'home' => 'home#index', :via => [:get, :post]
  end

  # Platform routes
  delete '/developer/apps/:id' => 'developer/apps#delete'
  put '/developer/apps/:id' => 'developer/apps#update'

  [:apps, :home, :login, :oauth, :forum, :ratings].each do |ctrl|
    controller "platform/#{ctrl}" do
      match "/#{ctrl}(/:action)", :via => [:get, :post]
    end
  end

  [:apps, :blog, :dashboard, :forum, :help, :issues, :registration, :resources].each do |ctrl|
    controller "platform/developer/#{ctrl}" do
      match "/developer/#{ctrl}(/:action(/:id))", :via => [:get, :post, :put, :delete]
    end
  end

  [:apps, :categories, :developers].each do |ctrl|
    match "/admin/#{ctrl}/:action" => "platform/admin/#{ctrl}#:action", :via => [:get, :post]
  end

  namespace :developer do
    root :to => 'dashboard#index'
  end

  namespace :admin do
    root :to => 'apps#index'
  end

  root :to => 'home#index'
end
