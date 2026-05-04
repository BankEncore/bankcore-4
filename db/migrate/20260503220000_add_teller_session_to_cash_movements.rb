# frozen_string_literal: true

class AddTellerSessionToCashMovements < ActiveRecord::Migration[8.1]
  def change
    add_reference :cash_movements, :teller_session, null: true, foreign_key: true
    add_index :cash_movements, [ :teller_session_id, :status ],
      name: "idx_cash_movements_on_teller_session_and_status"
  end
end
