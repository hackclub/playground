Rails.application.routes.draw do
  root "landing#show"

  get "dashboard" => "dashboard#show"
  get "guide" => "guides#show"
  get "requirements" => "requirements#show"
  resources :projects do
    get :checks, on: :member
    get :trash, on: :member
    post :ship, on: :member
    resources :screenshots, only: %i[create destroy] do
      patch :order, on: :collection
    end
  end
  resource :trash, only: :update, controller: "trash"
  resource :slack_channel, only: [] do
    post :join
    post :dismiss
  end
  resources :redemptions, only: %i[new create]

  get "auth/:provider/callback" => "sessions#create"
  get "auth/failure" => "sessions#failure"
  get "login" => "sessions#new"
  get "login/hackatime" => "sessions#hackatime_step", as: :hackatime_step
  delete "logout" => "sessions#destroy"

  if Rails.env.local?
    get "dev/login" => "sessions#dev"
    post "dev/hackatime" => "dev#hackatime"
  end

  namespace :admin do
    root "home#show"
    get "review" => "queues#review"
    get "fraud" => "queues#fraud"
    get "fulfillment" => "queues#fulfillment"
    resources :ships, only: :show do
      member do
        post :review
        post :fraud
        patch :checklist
      end
    end
    resources :redemptions, only: :show do
      member do
        post :reveal
        post :verdict
      end
    end
    resources :people, only: [ :index, :show ]
    get "stats" => "stats#show"
    post "claims/heartbeat" => "claims#heartbeat"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
