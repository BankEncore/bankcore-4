# frozen_string_literal: true

class CreateDepositProductOverdraftPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_product_overdraft_policies do |t|
      t.references :deposit_product, null: false, foreign_key: true
      t.string :mode, null: false
      t.bigint :nsf_fee_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "active"
      t.date :effective_on, null: false
      t.date :ended_on
      t.string :description
      t.timestamps
    end

    add_index :deposit_product_overdraft_policies,
      [ :deposit_product_id, :mode, :status, :effective_on, :ended_on ],
      name: "idx_deposit_product_od_policies_resolver"
    add_check_constraint :deposit_product_overdraft_policies, "nsf_fee_minor_units > 0",
      name: "deposit_product_od_policies_nsf_fee_positive"
    add_check_constraint :deposit_product_overdraft_policies, "mode IN ('deny_nsf')",
      name: "deposit_product_od_policies_mode_enum"
    add_check_constraint :deposit_product_overdraft_policies, "status IN ('active','inactive')",
      name: "deposit_product_od_policies_status_enum"
    add_check_constraint :deposit_product_overdraft_policies, "ended_on IS NULL OR ended_on >= effective_on",
      name: "deposit_product_od_policies_ended_on_after_effective_on"
  end
end
