# frozen_string_literal: true

class CreateDepositStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_statements do |t|
      t.references :deposit_account, null: false, foreign_key: true
      t.references :deposit_product_statement_profile,
        null: false,
        foreign_key: true,
        index: { name: "idx_deposit_statements_on_statement_profile_id" }
      t.date :period_start_on, null: false
      t.date :period_end_on, null: false
      t.string :currency, null: false, default: "USD"
      t.bigint :opening_ledger_balance_minor_units, null: false
      t.bigint :closing_ledger_balance_minor_units, null: false
      t.bigint :total_debits_minor_units, null: false, default: 0
      t.bigint :total_credits_minor_units, null: false, default: 0
      t.jsonb :line_items, null: false, default: []
      t.string :status, null: false, default: "generated"
      t.date :generated_on, null: false
      t.datetime :generated_at, null: false
      t.string :idempotency_key, null: false
      t.timestamps
    end

    add_index :deposit_statements, [ :deposit_account_id, :period_start_on, :period_end_on ],
      unique: true,
      name: "idx_deposit_statements_account_period_unique"
    add_index :deposit_statements, :idempotency_key, unique: true
    add_check_constraint :deposit_statements, "period_start_on <= period_end_on",
      name: "deposit_statements_period_valid"
    add_check_constraint :deposit_statements, "status IN ('generated')",
      name: "deposit_statements_status_enum"
    add_check_constraint :deposit_statements, "total_debits_minor_units >= 0",
      name: "deposit_statements_total_debits_non_negative"
    add_check_constraint :deposit_statements, "total_credits_minor_units >= 0",
      name: "deposit_statements_total_credits_non_negative"
  end
end
