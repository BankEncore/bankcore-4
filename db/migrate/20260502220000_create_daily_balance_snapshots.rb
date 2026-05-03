# frozen_string_literal: true

class CreateDailyBalanceSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_balance_snapshots do |t|
      t.string :account_domain, null: false
      t.bigint :account_id, null: false
      t.string :account_type
      t.date :as_of_date, null: false
      t.bigint :ledger_balance_minor_units, null: false
      t.bigint :hold_balance_minor_units, null: false, default: 0
      t.bigint :available_balance_minor_units, null: false
      t.bigint :collected_balance_minor_units
      t.string :source, null: false
      t.integer :calculation_version, null: false
      t.timestamps
    end

    add_index :daily_balance_snapshots,
      [ :account_domain, :account_id, :as_of_date ],
      unique: true,
      name: "idx_daily_balance_snapshots_account_date"
    add_index :daily_balance_snapshots,
      [ :account_domain, :as_of_date ],
      name: "idx_daily_balance_snapshots_domain_date"
    add_index :daily_balance_snapshots,
      :as_of_date,
      name: "idx_daily_balance_snapshots_as_of_date"

    add_check_constraint :daily_balance_snapshots,
      "hold_balance_minor_units >= 0",
      name: "chk_daily_balance_snapshots_hold_non_negative"
    add_check_constraint :daily_balance_snapshots,
      "calculation_version > 0",
      name: "chk_daily_balance_snapshots_calc_version_positive"
  end
end
