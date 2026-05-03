# frozen_string_literal: true

class HardenDailyBalanceSnapshotVersioning < ActiveRecord::Migration[8.1]
  def change
    remove_index :daily_balance_snapshots, name: "idx_daily_balance_snapshots_account_date"

    add_column :daily_balance_snapshots, :stale, :boolean, null: false, default: false
    add_column :daily_balance_snapshots, :stale_from_date, :date

    add_index :daily_balance_snapshots,
      [ :account_domain, :account_id, :as_of_date, :source, :calculation_version ],
      unique: true,
      name: "idx_daily_balance_snapshots_account_date_source_version"
    add_index :daily_balance_snapshots,
      [ :stale, :stale_from_date ],
      name: "idx_daily_balance_snapshots_stale_from_date"
  end
end
