# frozen_string_literal: true

class CreateDepositBalanceRebuildRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_balance_rebuild_requests do |t|
      t.references :deposit_account, null: false, foreign_key: true, index: { name: "idx_deposit_balance_rebuild_requests_account" }
      t.string :rebuild_type, null: false
      t.string :reason, null: false
      t.string :status, null: false
      t.date :rebuild_from_date
      t.date :rebuild_through_date
      t.references :source_operational_event,
        foreign_key: { to_table: :operational_events },
        index: { name: "idx_deposit_balance_rebuild_requests_source_event" }
      t.integer :calculation_version, null: false
      t.datetime :requested_at, null: false
      t.datetime :processed_at
      t.timestamps
    end

    add_index :deposit_balance_rebuild_requests,
      [ :status, :requested_at ],
      name: "idx_deposit_balance_rebuild_requests_status_requested"
    add_index :deposit_balance_rebuild_requests,
      [ :deposit_account_id, :status ],
      name: "idx_deposit_balance_rebuild_requests_account_status"
    add_check_constraint :deposit_balance_rebuild_requests,
      "calculation_version > 0",
      name: "chk_deposit_balance_rebuild_requests_calc_version_positive"
  end
end
