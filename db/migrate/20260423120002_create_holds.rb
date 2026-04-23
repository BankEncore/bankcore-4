# frozen_string_literal: true

class CreateHolds < ActiveRecord::Migration[8.1]
  def change
    create_table :holds do |t|
      t.references :deposit_account, null: false, foreign_key: true
      t.bigint :amount_minor_units, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "active"
      t.references :placed_by_operational_event, null: true, foreign_key: { to_table: :operational_events }
      t.references :released_by_operational_event, null: true, foreign_key: { to_table: :operational_events }
      t.timestamps
    end

    add_check_constraint :holds, "amount_minor_units > 0", name: "holds_amount_positive"
    add_check_constraint :holds, "status IN ('active','released','expired')", name: "holds_status_enum"
  end
end
