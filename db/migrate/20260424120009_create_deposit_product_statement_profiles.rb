# frozen_string_literal: true

class CreateDepositProductStatementProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_product_statement_profiles do |t|
      t.references :deposit_product, null: false, foreign_key: true
      t.string :frequency, null: false
      t.integer :cycle_day, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "active"
      t.date :effective_on, null: false
      t.date :ended_on
      t.string :description
      t.timestamps
    end

    add_index :deposit_product_statement_profiles,
      [ :deposit_product_id, :frequency, :status, :effective_on, :ended_on ],
      name: "idx_deposit_product_statement_profiles_resolver"
    add_check_constraint :deposit_product_statement_profiles, "frequency IN ('monthly')",
      name: "deposit_product_statement_profiles_frequency_enum"
    add_check_constraint :deposit_product_statement_profiles, "cycle_day BETWEEN 1 AND 31",
      name: "deposit_product_statement_profiles_cycle_day_range"
    add_check_constraint :deposit_product_statement_profiles, "status IN ('active','inactive')",
      name: "deposit_product_statement_profiles_status_enum"
    add_check_constraint :deposit_product_statement_profiles, "ended_on IS NULL OR ended_on >= effective_on",
      name: "deposit_product_statement_profiles_ended_on_after_effective_on"
  end
end
