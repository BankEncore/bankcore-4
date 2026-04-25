Rails.application.routes.draw do
  get "login", to: "internal/sessions#new", as: :login
  post "login", to: "internal/sessions#create"
  delete "logout", to: "internal/sessions#destroy", as: :logout

  get "internal", to: "internal/dashboard#index", as: :internal
  get "branch", to: "branch/dashboard#index", as: :branch
  scope path: "branch", module: :branch, as: :branch do
    resources :parties, only: [ :new, :create ]
    resources :deposit_accounts, only: [ :new, :create ]
    resources :deposits, only: [ :new, :create ]
    resources :withdrawals, only: [ :new, :create ]
    post "operational_events/:id/post", to: "operational_event_posts#create", as: :operational_event_post
  end
  get "ops", to: "ops/dashboard#index", as: :ops
  scope path: "ops", module: :ops, as: :ops do
    get "eod", to: "eod#index", as: :eod
    resources :operational_events, only: [ :index, :show ]
  end
  get "admin", to: "admin/dashboard#index", as: :admin
  scope path: "admin", module: :admin, as: :admin do
    resources :deposit_products, only: [ :index, :show ]
    resources :deposit_product_fee_rules, only: [ :index ]
    resources :deposit_product_overdraft_policies, only: [ :index ]
    resources :deposit_product_statement_profiles, only: [ :index ]
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  scope path: "teller", defaults: { format: :json }, module: :teller do
    post "parties", to: "parties#create"
    post "deposit_accounts", to: "deposit_accounts#create"
    get "event_types", to: "event_types#index"
    get "operational_events", to: "operational_events#index"
    post "operational_events", to: "operational_events#create"
    post "operational_events/:id/post", to: "operational_event_posts#create"
    post "reversals", to: "reversals#create"
    post "holds", to: "holds#create"
    post "holds/release", to: "holds#release"
    post "teller_sessions", to: "teller_sessions#create"
    post "teller_sessions/close", to: "teller_sessions#close"
    post "teller_sessions/approve_variance", to: "teller_sessions#approve_variance"
    post "overrides", to: "overrides#create"
    get "reports/trial_balance", to: "reports#trial_balance"
    get "reports/eod_readiness", to: "reports#eod_readiness"
    post "business_date/close", to: "business_date_closes#create"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
