require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BankCore4
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Ledger uses PostgreSQL triggers; structure.sql (pg_dump) preserves them. schema.rb cannot.
    config.active_record.schema_format = :sql

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Bounded domains (commands, queries, models, …) per docs/architecture/bankcore-module-catalog.md
    # and docs/adr/0001-modular-monolith-architecture-with-domain-boundaries.md.
    # Example: app/domains/party/models/party_record.rb -> Party::Models::PartyRecord
    domains_root = root.join("app/domains")
    config.autoload_paths << domains_root
    config.eager_load_paths << domains_root

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Eastern Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
