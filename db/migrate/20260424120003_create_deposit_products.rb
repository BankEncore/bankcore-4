# frozen_string_literal: true

class CreateDepositProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_products do |t|
      t.string :product_code, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "active"
      t.string :currency, null: false, default: "USD"
      t.timestamps
    end

    add_index :deposit_products, :product_code, unique: true
  end
end
