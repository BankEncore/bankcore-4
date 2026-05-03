# frozen_string_literal: true

class CreateDepositAccountBalanceProjections < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_account_balance_projections do |t|
      t.references :deposit_account,
        null: false,
        foreign_key: true,
        index: { unique: true, name: "idx_deposit_balance_proj_account_unique" }
      t.bigint :ledger_balance_minor_units, null: false, default: 0
      t.bigint :hold_balance_minor_units, null: false, default: 0
      t.bigint :available_balance_minor_units, null: false, default: 0
      t.bigint :collected_balance_minor_units
      t.references :last_journal_entry,
        foreign_key: { to_table: :journal_entries },
        index: { name: "idx_deposit_balance_proj_last_journal_entry" }
      t.references :last_operational_event,
        foreign_key: { to_table: :operational_events },
        index: { name: "idx_deposit_balance_proj_last_operational_event" }
      t.date :as_of_business_date
      t.datetime :last_calculated_at
      t.boolean :stale, null: false, default: false
      t.date :stale_from_date
      t.integer :calculation_version, null: false, default: 1
      t.timestamps
    end

    add_index :deposit_account_balance_projections,
      [ :stale, :stale_from_date ],
      name: "idx_deposit_balance_proj_stale_from_date"
    add_index :deposit_account_balance_projections,
      :as_of_business_date,
      name: "idx_deposit_balance_proj_as_of_business_date"

    add_check_constraint :deposit_account_balance_projections,
      "hold_balance_minor_units >= 0",
      name: "chk_deposit_balance_proj_hold_non_negative"
    add_check_constraint :deposit_account_balance_projections,
      "calculation_version > 0",
      name: "chk_deposit_balance_proj_calculation_version_positive"
  end
end
