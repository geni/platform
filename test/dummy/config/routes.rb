Rails.application.routes.draw do
  # This will also mount Tr8n::Engine at /tr8n and WillFilter::Engine at will_filter
  mount Platform::Engine => "/platform"

  get '/login', to: 'dummy#index', as: :login
  get '/dummy/switch_user', to: 'dummy#switch_user', as: :switch_user
  get '/', to: 'dummy#index', as: :root
end
