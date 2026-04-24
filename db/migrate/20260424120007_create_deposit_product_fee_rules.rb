# frozen_string_literal: true

class CreateDepositProductFeeRules < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_product_fee_rules do |t|
      t.references :deposit_product, null: false, foreign_key: true
      t.string :fee_code, null: false
      t.bigint :amount_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "active"
      t.date :effective_on, null: false
      t.date :ended_on
      t.string :description
      t.timestamps
    end

    add_index :deposit_product_fee_rules,
      [ :deposit_product_id, :fee_code, :status, :effective_on, :ended_on ],
      name: "idx_deposit_product_fee_rules_resolver"
    add_check_constraint :deposit_product_fee_rules, "amount_minor_units > 0",
      name: "deposit_product_fee_rules_amount_positive"
    add_check_constraint :deposit_product_fee_rules, "status IN ('active','inactive')",
      name: "deposit_product_fee_rules_status_enum"
    add_check_constraint :deposit_product_fee_rules, "ended_on IS NULL OR ended_on >= effective_on",
      name: "deposit_product_fee_rules_ended_on_after_effective_on"
  end
end
