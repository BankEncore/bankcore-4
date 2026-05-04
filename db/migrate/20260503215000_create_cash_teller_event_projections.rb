# frozen_string_literal: true

class CreateCashTellerEventProjections < ActiveRecord::Migration[8.1]
  PROJECTION_TYPES = %w[teller_cash_event teller_cash_reversal].freeze
  EVENT_TYPES = %w[deposit.accepted withdrawal.posted posting.reversal].freeze

  def change
    create_table :cash_teller_event_projections do |t|
      t.references :operational_event, null: false, foreign_key: true, index: { unique: true }
      t.references :reversal_of_operational_event, null: true, foreign_key: { to_table: :operational_events }
      t.references :teller_session, null: false, foreign_key: true
      t.references :cash_location, null: false, foreign_key: true
      t.string :projection_type, null: false
      t.string :event_type, null: false
      t.bigint :amount_minor_units, null: false
      t.bigint :delta_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.date :business_date, null: false
      t.datetime :applied_at, null: false
      t.timestamps
    end

    add_check_constraint :cash_teller_event_projections,
      "amount_minor_units > 0",
      name: "cash_teller_event_projections_positive_amount_check"
    add_check_constraint :cash_teller_event_projections,
      "delta_minor_units <> 0",
      name: "cash_teller_event_projections_nonzero_delta_check"
    add_check_constraint :cash_teller_event_projections,
      "currency = 'USD'",
      name: "cash_teller_event_projections_currency_usd_check"
    add_check_constraint :cash_teller_event_projections,
      in_list_sql("projection_type", PROJECTION_TYPES),
      name: "cash_teller_event_projections_type_check"
    add_check_constraint :cash_teller_event_projections,
      in_list_sql("event_type", EVENT_TYPES),
      name: "cash_teller_event_projections_event_type_check"
    add_index :cash_teller_event_projections, [ :business_date, :applied_at, :id ],
      name: "idx_cash_teller_event_projections_rebuild_order"
    add_index :cash_teller_event_projections, :cash_location_id,
      name: "idx_cash_teller_event_projections_on_cash_location"
  end

  private

  def in_list_sql(column_name, values)
    quoted = values.map { |value| connection.quote(value) }.join(", ")
    "#{column_name} IN (#{quoted})"
  end
end
