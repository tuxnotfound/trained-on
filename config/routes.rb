Rails.application.routes.draw do
  root "registry#index"

  # Before the vendor resource, which would otherwise take ".atom" as a format.
  get "vendors/:slug.atom", to: "feeds#vendor", as: :vendor_feed, defaults: { format: :atom }
  resources :vendors, only: :show, param: :slug
  get "changes.atom", to: "feeds#changes", as: :changes_feed, defaults: { format: :atom }
  resources :changes, only: %i[index show], param: :slug

  get "methodology", to: "pages#methodology"
  get "data", to: "pages#data"

  namespace :api do
    namespace :v1 do
      get "vendors", to: "vendors#index", defaults: { format: :json }
      get "changes", to: "changes#index", defaults: { format: :json }
    end
  end
  get "data/registry.csv", to: "api/v1/vendors#index", defaults: { format: :csv }, as: :registry_csv
  get "data/changes.csv", to: "api/v1/changes#index", defaults: { format: :csv }, as: :changes_csv

  namespace :admin do
    root "events#index"
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout
    resources :events, only: %i[index show update] do
      post :panel, on: :member
    end
    post "panel", to: "panel#run", as: :panel
    resources :tiers, only: :update
    resources :documents, only: :show do
      post :rebuild, on: :member
      resources :anchors, only: %i[create destroy]
    end
    post "preview", to: "preview#toggle"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
