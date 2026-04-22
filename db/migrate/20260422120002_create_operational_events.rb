# frozen_string_literal: true

class CreateOperationalEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :operational_events do |t|
      t.string :event_type, null: false
      t.string :status, null: false
      t.date :business_date, null: false
      t.string :idempotency_key, null: false
      t.bigint :amount_minor_units
      t.string :currency

      t.timestamps
    end

    add_index :operational_events, :idempotency_key, unique: true
  end
end
