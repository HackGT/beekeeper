Rails.application.routes.draw do
  namespace :api do
    resources :github_webhooks, only: [:create], defaults: { formats: :json }
    resources :version_updates, only: [:create], defaults: { formats: :json }
  end  
end
