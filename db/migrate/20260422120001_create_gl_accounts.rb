# frozen_string_literal: true

class CreateGlAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :gl_accounts do |t|
      t.string :account_number, null: false
      t.string :account_type, null: false
      t.string :natural_balance, null: false
      t.string :account_name, null: false
      t.string :currency, null: false, default: "USD"
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :gl_accounts, :account_number, unique: true
  end
end
