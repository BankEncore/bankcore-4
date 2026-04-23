# frozen_string_literal: true

class AddTransferAndReversalColumnsToOperationalEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :operational_events, :destination_account, foreign_key: { to_table: :deposit_accounts }, null: true

    add_column :operational_events, :reversal_of_event_id, :bigint
    add_column :operational_events, :reversed_by_event_id, :bigint

    add_foreign_key :operational_events, :operational_events, column: :reversal_of_event_id
    add_foreign_key :operational_events, :operational_events, column: :reversed_by_event_id

    add_index :operational_events, :reversal_of_event_id, unique: true, where: "reversal_of_event_id IS NOT NULL",
      name: "index_operational_events_one_reversal_per_original"
  end
end
