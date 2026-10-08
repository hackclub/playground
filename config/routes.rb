Rails.application.routes.draw do
  root "landing#show"

  get "dashboard" => "dashboard#show"
  get "guide" => "guides#show"
  get "requirements" => "requirements#show"
  # nps.exe's form, and its answers.
  resource :nps, only: %i[show create], controller: "nps_responses"
  # The guide for readers who come from Stardance or from a club, open to
  # everyone, with nothing that needs an account (SideGuide): /stardance,
  # /stardance/move, /clubs.
  get ":guide(/:step)" => "side_guides#show", as: :side_guide, constraints: { guide: /stardance|clubs/, step: /[a-z]+/ }
  # A building block's page (BuildingBlock), open to everyone, from the
  # guide's "Make it your own" step: /guide/blocks/sound-effect, or from a
  # side guide, /clubs/blocks/sound-effect.
  get ":guide/blocks/:block" => "building_blocks#show", as: :building_block,
                                constraints: { guide: /guide|stardance|clubs/, block: /[a-z0-9-]+/ }
  # A browser that read one of them long enough on a day says so, once.
  post "guide_readers" => "guide_readers#create", as: :guide_readers
  # A browser says which sections of a guide it reached, each once.
  post "guide_sections" => "guide_sections#create", as: :guide_sections
  # A browser says how far it got in a guide, and how long it spent there.
  post "guide_journeys" => "guide_journeys#create", as: :guide_journeys
  resources :projects do
    get :checks, on: :member
    get :trash, on: :member
    post :ship, on: :member
    resources :screenshots, only: %i[create destroy] do
      patch :order, on: :collection
    end
  end
  resource :trash, only: :update, controller: "trash"

  # The new site's own addresses, for visitors and users with the new site
  # on (NewSite). Account actions still require login in their controllers.
  constraints(->(request) { NewSite.request?(request) }) do
    # The guide's steps that act on the site, each a frame inside the guide.
    scope "guide", controller: "guide_steps", as: "guide" do
      get "check", action: :check
      get "side", action: :side
      get "ship", action: :ship
      post "link", action: :link
    end
    # Each step of the guide at its own address, such as /guide/move. /guide
    # shows the first. A name that is no step's is not found.
    get "guide/:step" => "guides#show", as: :guide_page, constraints: { step: /[a-z]+/ }
    # The pet the guide acts on, which the participant sets from the guide
    # and from my pets.
    resource :active_pet, only: :update
    # A pet's ship page, and its delete page, which asks first.
    resources :projects, only: [] do
      get :ship, on: :member, action: :checks
      get :delete, on: :member
    end
  end
  # Switching one browser to the old desktop and back, for a user with the
  # new site on (NewSite). For anyone else it does not exist.
  constraints(->(request) { NewSite.flagged?(request) }) do
    resource :classic, only: %i[show create destroy], controller: "classic"
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
    post "dev/heartbeat" => "dev#heartbeat"
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
    resources :people, only: [ :index, :show ] do
      patch :new_site, on: :member
    end
    get "stats" => "stats#show"
    post "claims/heartbeat" => "claims#heartbeat"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
