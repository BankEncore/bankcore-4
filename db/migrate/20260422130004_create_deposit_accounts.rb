# frozen_string_literal: true

class CreateDepositAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_accounts do |t|
      t.string :account_number, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false
      t.string :product_code, null: false
      t.timestamps
    end

    add_index :deposit_accounts, :account_number, unique: true
  end
end
