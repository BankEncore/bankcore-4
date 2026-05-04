Rails.application.routes.draw do
  get "login", to: "internal/sessions#new", as: :login
  post "login", to: "internal/sessions#create"
  delete "logout", to: "internal/sessions#destroy", as: :logout

  get "internal", to: "internal/dashboard#index", as: :internal
  get "branch", to: "branch/dashboard#index", as: :branch
  scope path: "branch", module: :branch, as: :branch do
    get "teller", to: "dashboard#teller", as: :teller
    get "approvals", to: "dashboard#approvals", as: :approvals
    get "servicing", to: redirect("/branch/customers")
    resources :customers, only: [ :index, :show ]
    resources :parties, only: [ :new, :create ]
    get "customers/:party_record_id/contacts/new", to: "party_contacts#new", as: :new_party_contact
    post "customers/:party_record_id/contacts", to: "party_contacts#create", as: :party_contacts
    resources :deposit_accounts, only: [ :new, :create ]
    resources :accounts, controller: "servicing_deposit_accounts", only: [ :show ]
    get "deposit_accounts/:id", to: "servicing_deposit_accounts#show", as: :servicing_deposit_account
    get "deposit_accounts/:deposit_account_id/activity", to: "account_activities#show", as: :account_activity
    get "deposit_accounts/:deposit_account_id/authorized_signers/new",
      to: "account_parties#new_authorized_signer",
      as: :new_account_authorized_signer
    post "deposit_accounts/:deposit_account_id/authorized_signers",
      to: "account_parties#create_authorized_signer",
      as: :account_authorized_signers
    get "deposit_accounts/:deposit_account_id/authorized_signers/:relationship_id/end",
      to: "account_parties#end_authorized_signer",
      as: :end_account_authorized_signer
    post "deposit_accounts/:deposit_account_id/authorized_signers/:relationship_id/end",
      to: "account_parties#create_end_authorized_signer"
    get "deposit_accounts/:deposit_account_id/holds", to: "account_holds#index", as: :account_holds
    get "deposit_accounts/:deposit_account_id/holds/new", to: "account_holds#new", as: :new_account_hold
    post "deposit_accounts/:deposit_account_id/holds", to: "account_holds#create", as: :account_hold_placements
    get "deposit_accounts/:deposit_account_id/holds/:hold_id/release", to: "account_holds#release", as: :release_account_hold
    post "deposit_accounts/:deposit_account_id/holds/:hold_id/release", to: "account_holds#create_release"
    get "deposit_accounts/:deposit_account_id/restrictions/new",
      to: "account_restrictions#new",
      as: :new_account_restriction
    post "deposit_accounts/:deposit_account_id/restrictions",
      to: "account_restrictions#create",
      as: :account_restrictions
    post "deposit_accounts/:deposit_account_id/restrictions/:id/release",
      to: "account_restrictions#release",
      as: :release_account_restriction
    get "deposit_accounts/:deposit_account_id/close",
      to: "account_closes#new",
      as: :close_account
    post "deposit_accounts/:deposit_account_id/close",
      to: "account_closes#create"
    get "deposit_accounts/:deposit_account_id/statements", to: "account_statements#index", as: :account_statements
    get "deposit_accounts/:deposit_account_id/fee_assessments/new", to: "fee_assessments#new", as: :new_fee_assessment
    post "deposit_accounts/:deposit_account_id/fee_assessments", to: "fee_assessments#create", as: :fee_assessments
    get "deposit_accounts/:deposit_account_id/fee_waivers/new", to: "fee_waivers#new", as: :new_fee_waiver
    post "deposit_accounts/:deposit_account_id/fee_waivers", to: "fee_waivers#create", as: :fee_waivers
    resources :teller_sessions, only: [ :new, :create ] do
      collection do
        post :approve_variance
      end
      post :close, on: :member
    end
    get "cash", to: "cash#index", as: :cash
    get "cash/transfers/new", to: "cash#new_transfer", as: :new_cash_transfer
    post "cash/transfers", to: "cash#create_transfer", as: :cash_transfers
    get "cash/shipments/received/new", to: "cash#new_external_shipment", as: :new_external_cash_shipment
    post "cash/shipments/received", to: "cash#create_external_shipment", as: :external_cash_shipments
    get "cash/counts/new", to: "cash#new_count", as: :new_cash_count
    post "cash/counts", to: "cash#create_count", as: :cash_counts
    get "cash/locations/:id", to: "cash#show_location", as: :cash_location
    post "cash/movements/:id/approve", to: "cash#approve_movement", as: :approve_cash_movement
    post "cash/variances/:id/approve", to: "cash#approve_variance", as: :approve_cash_variance
    resources :deposits, only: [ :new, :create ]
    resources :check_deposits, only: [ :new, :create ]
    resources :withdrawals, only: [ :new, :create ]
    resources :transfers, only: [ :new, :create ]
    resources :holds, only: [ :new, :create ] do
      collection do
        get :release
        post :release, action: :create_release
      end
    end
    resources :reversals, only: [ :new, :create ]
    resources :overrides, only: [ :new, :create ]
    resources :events, controller: "operational_events", only: [ :index, :show ]
    get "events/:id/receipt", to: "operational_events#receipt", as: :event_receipt
    post "events/:id/post", to: "operational_event_posts#create", as: :event_post
    resources :operational_events, only: [ :index, :show ]
    get "operational_events/:id/receipt", to: "operational_events#receipt", as: :operational_event_receipt
    post "operational_events/:id/post", to: "operational_event_posts#create", as: :operational_event_post
  end
  get "ops", to: "ops/dashboard#index", as: :ops
  scope path: "ops", module: :ops, as: :ops do
    get "eod", to: "eod#index", as: :eod
    get "business_date_close", to: "business_date_closes#new", as: :business_date_close
    post "business_date_close", to: "business_date_closes#create"
    get "close_package", to: "close_packages#show", as: :close_package
    get "exceptions", to: "exceptions#index", as: :exceptions
    get "engine_runs", to: "engine_runs#index", as: :engine_runs
    get "engine_runs/:engine/new", to: "engine_runs#new", as: :new_engine_run
    post "engine_runs/:engine", to: "engine_runs#create", as: :engine_run
    get "balance_projections", to: "balance_projections#index", as: :balance_projections
    post "balance_projections/:deposit_account_id/mark_stale",
      to: "balance_projections#mark_stale",
      as: :mark_stale_balance_projection
    post "balance_projections/:deposit_account_id/rebuild",
      to: "balance_projections#rebuild",
      as: :rebuild_balance_projection
    get "balance_projections/bulk_repair",
      to: "balance_projections#bulk_repair",
      as: :balance_projection_bulk_repair
    post "balance_projections/bulk_repair", to: "balance_projections#create_bulk_repair"
    get "ach_receipt_ingestions/new", to: "ach_receipt_ingestions#new", as: :new_ach_receipt_ingestion
    post "ach_receipt_ingestions", to: "ach_receipt_ingestions#create", as: :ach_receipt_ingestions
    resources :teller_variances, only: [ :index ] do
      post :approve, on: :member, action: :create
    end
    resources :teller_sessions, only: %i[index show]
    get "cash", to: "cash#index", as: :cash
    post "cash/movements/:id/approve", to: "cash#approve_movement", as: :approve_cash_movement
    post "cash/variances/:id/approve", to: "cash#approve_variance", as: :approve_cash_variance
    get "cash/reconciliation", to: "cash#reconciliation", as: :cash_reconciliation
    resources :operational_events, only: [ :index, :show ]
  end
  get "admin", to: "admin/dashboard#index", as: :admin
  scope path: "admin", module: :admin, as: :admin do
    resources :operators do
      post :deactivate, on: :member
      post :reset_credential, on: :member
      resources :operator_role_assignments, only: [ :new, :create, :edit, :update ] do
        post :deactivate, on: :member
      end
    end
    resources :roles do
      patch :capabilities, on: :member, action: :update_capabilities
      post :deactivate, on: :member
    end
    resources :capabilities do
      post :deactivate, on: :member
    end
    resources :operating_units do
      post :close, on: :member
    end
    resources :cash_locations do
      post :deactivate, on: :member
    end
    resources :deposit_products, only: [ :index, :show ]
    get "deposit_products/:id/readiness", to: "deposit_products#readiness", as: :deposit_product_readiness
    resources :deposit_product_fee_rules, only: [ :index ]
    resources :deposit_product_overdraft_policies, only: [ :index ]
    resources :deposit_product_statement_profiles, only: [ :index ]
    get "rule_changes/:rule_kind/new", to: "rule_changes#new", as: :new_rule_change
    post "rule_changes/:rule_kind/preview", to: "rule_changes#preview", as: :preview_rule_change
    post "rule_changes/:rule_kind", to: "rule_changes#create", as: :rule_changes
    post "rule_changes/:rule_kind/:id/end_date_preview", to: "rule_changes#preview_end_date", as: :preview_end_date_rule_change
    patch "rule_changes/:rule_kind/:id/end_date", to: "rule_changes#end_date", as: :end_date_rule_change
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
    get "cash/locations", to: "cash#locations"
    post "cash/locations", to: "cash#create_location"
    post "cash/transfers", to: "cash#create_transfer"
    post "cash/transfers/approve", to: "cash#approve_transfer"
    post "cash/counts", to: "cash#create_count"
    post "cash/variances/approve", to: "cash#approve_variance"
    get "cash/position", to: "cash#position"
    get "cash/activity", to: "cash#activity"
    get "cash/approvals", to: "cash#approvals"
    get "cash/reconciliation", to: "cash#reconciliation"
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
