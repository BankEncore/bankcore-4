# frozen_string_literal: true

class AddOpeningCashToTellerSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :teller_sessions, :opening_cash_minor_units, :bigint, null: false, default: 0

    execute <<~SQL.squish
      UPDATE teller_sessions
      SET opening_cash_minor_units = COALESCE(cash_balances.amount_minor_units, 0)
      FROM cash_balances
      WHERE teller_sessions.cash_location_id = cash_balances.cash_location_id
        AND teller_sessions.status = 'open'
    SQL
  end

  def down
    remove_column :teller_sessions, :opening_cash_minor_units
  end
end
