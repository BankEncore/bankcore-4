# frozen_string_literal: true

class CreateCashInventoryTables < ActiveRecord::Migration[8.1]
  LOCATION_TYPES = %w[branch_vault teller_drawer internal_transit].freeze
  LOCATION_STATUSES = %w[active inactive].freeze
  MOVEMENT_TYPES = %w[vault_to_drawer drawer_to_vault internal_transfer adjustment].freeze
  MOVEMENT_STATUSES = %w[pending_approval approved completed cancelled rejected].freeze
  COUNT_STATUSES = %w[recorded].freeze
  VARIANCE_STATUSES = %w[pending_approval approved posted].freeze

  def change
    create_table :cash_locations do |t|
      t.string :location_type, null: false
      t.references :operating_unit, null: false, foreign_key: true
      t.references :responsible_operator, null: true, foreign_key: { to_table: :operators }
      t.references :parent_cash_location, null: true, foreign_key: { to_table: :cash_locations }
      t.string :drawer_code
      t.string :name, null: false
      t.string :status, null: false, default: "active"
      t.string :currency, null: false, default: "USD"
      t.boolean :balancing_required, null: false, default: true
      t.string :external_reference
      t.timestamps
    end

    add_check_constraint :cash_locations, in_list_sql("location_type", LOCATION_TYPES), name: "cash_locations_type_check"
    add_check_constraint :cash_locations, in_list_sql("status", LOCATION_STATUSES), name: "cash_locations_status_check"
    add_check_constraint :cash_locations, "currency = 'USD'", name: "cash_locations_currency_usd_check"
    add_check_constraint :cash_locations, "parent_cash_location_id IS NULL OR parent_cash_location_id <> id",
      name: "cash_locations_parent_not_self_check"
    add_index :cash_locations, [ :operating_unit_id, :location_type, :drawer_code ],
      unique: true,
      where: "status = 'active' AND location_type = 'teller_drawer'",
      name: "idx_active_cash_drawer_identity"
    add_index :cash_locations, [ :operating_unit_id, :location_type ],
      unique: true,
      where: "status = 'active' AND location_type = 'branch_vault'",
      name: "idx_active_branch_vault_identity"

    create_table :cash_movements do |t|
      t.references :source_cash_location, null: true, foreign_key: { to_table: :cash_locations }
      t.references :destination_cash_location, null: true, foreign_key: { to_table: :cash_locations }
      t.references :operating_unit, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.references :approving_actor, null: true, foreign_key: { to_table: :operators }
      t.references :operational_event, null: true, foreign_key: true
      t.bigint :amount_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.date :business_date, null: false
      t.string :status, null: false, default: "completed"
      t.string :movement_type, null: false
      t.string :reason_code
      t.string :idempotency_key, null: false
      t.string :request_fingerprint, null: false
      t.datetime :approved_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.datetime :rejected_at
      t.timestamps
    end

    add_check_constraint :cash_movements, "amount_minor_units > 0", name: "cash_movements_positive_amount_check"
    add_check_constraint :cash_movements, "currency = 'USD'", name: "cash_movements_currency_usd_check"
    add_check_constraint :cash_movements, in_list_sql("status", MOVEMENT_STATUSES), name: "cash_movements_status_check"
    add_check_constraint :cash_movements, in_list_sql("movement_type", MOVEMENT_TYPES), name: "cash_movements_type_check"
    add_check_constraint :cash_movements,
      "source_cash_location_id IS NOT NULL OR destination_cash_location_id IS NOT NULL",
      name: "cash_movements_location_present_check"
    add_index :cash_movements, :idempotency_key, unique: true
    add_index :cash_movements, [ :business_date, :id ]

    create_table :cash_balances do |t|
      t.references :cash_location, null: false, foreign_key: true
      t.string :currency, null: false, default: "USD"
      t.bigint :amount_minor_units, null: false, default: 0
      t.references :last_cash_movement, null: true, foreign_key: { to_table: :cash_movements }
      t.bigint :last_cash_count_id
      t.timestamps
    end

    add_check_constraint :cash_balances, "currency = 'USD'", name: "cash_balances_currency_usd_check"
    add_index :cash_balances, [ :cash_location_id, :currency ], unique: true

    create_table :cash_counts do |t|
      t.references :cash_location, null: false, foreign_key: true
      t.references :operating_unit, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.references :operational_event, null: true, foreign_key: true
      t.bigint :counted_amount_minor_units, null: false
      t.bigint :expected_amount_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.date :business_date, null: false
      t.string :status, null: false, default: "recorded"
      t.string :idempotency_key, null: false
      t.string :request_fingerprint, null: false
      t.timestamps
    end

    add_check_constraint :cash_counts, "counted_amount_minor_units >= 0", name: "cash_counts_nonnegative_counted_check"
    add_check_constraint :cash_counts, "expected_amount_minor_units >= 0", name: "cash_counts_nonnegative_expected_check"
    add_check_constraint :cash_counts, "currency = 'USD'", name: "cash_counts_currency_usd_check"
    add_check_constraint :cash_counts, in_list_sql("status", COUNT_STATUSES), name: "cash_counts_status_check"
    add_index :cash_counts, :idempotency_key, unique: true
    add_index :cash_counts, [ :business_date, :id ]
    add_foreign_key :cash_balances, :cash_counts, column: :last_cash_count_id

    create_table :cash_variances do |t|
      t.references :cash_location, null: false, foreign_key: true
      t.references :cash_count, null: false, foreign_key: true, index: { unique: true }
      t.references :operating_unit, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.references :approving_actor, null: true, foreign_key: { to_table: :operators }
      t.references :cash_variance_posted_event, null: true, foreign_key: { to_table: :operational_events },
        index: { unique: true }
      t.bigint :amount_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.date :business_date, null: false
      t.string :status, null: false, default: "pending_approval"
      t.datetime :approved_at
      t.datetime :posted_at
      t.timestamps
    end

    add_check_constraint :cash_variances, "amount_minor_units <> 0", name: "cash_variances_nonzero_amount_check"
    add_check_constraint :cash_variances, "currency = 'USD'", name: "cash_variances_currency_usd_check"
    add_check_constraint :cash_variances, in_list_sql("status", VARIANCE_STATUSES), name: "cash_variances_status_check"
    add_reference :teller_sessions, :cash_location, null: true, foreign_key: true
  end

  private

  def in_list_sql(column_name, values)
    quoted = values.map { |value| connection.quote(value) }.join(", ")
    "#{column_name} IN (#{quoted})"
  end
end
