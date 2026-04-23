# frozen_string_literal: true

class CreateOperatorsAndOperationalEventsActorFk < ActiveRecord::Migration[8.1]
  def change
    create_table :operators do |t|
      t.string :role, null: false
      t.string :display_name
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_check_constraint :operators, "role IN ('teller', 'supervisor')", name: "operators_role_check"

    add_foreign_key :operational_events, :operators, column: :actor_id, validate: true
  end
end
