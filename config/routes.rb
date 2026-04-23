Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  scope path: "teller", defaults: { format: :json }, module: :teller do
    post "parties", to: "parties#create"
    post "deposit_accounts", to: "deposit_accounts#create"
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
