# frozen_string_literal: true

class AddSupervisorOperatorIdToTellerSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :teller_sessions, :supervisor_operator, foreign_key: { to_table: :operators }, null: true
  end
end
