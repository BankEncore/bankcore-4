# frozen_string_literal: true

class CreateTellerSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :teller_sessions do |t|
      t.string :status, null: false, default: "open"
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.string :drawer_code
      t.bigint :expected_cash_minor_units
      t.bigint :actual_cash_minor_units
      t.bigint :variance_minor_units
      t.datetime :supervisor_approved_at
      t.timestamps
    end

    add_check_constraint :teller_sessions, "status IN ('open','closed','pending_supervisor')",
      name: "teller_sessions_status_enum"
  end
end
