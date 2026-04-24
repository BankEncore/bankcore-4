# frozen_string_literal: true

class AddPlacedForOperationalEventIdToHolds < ActiveRecord::Migration[8.1]
  def change
    add_reference :holds, :placed_for_operational_event, foreign_key: { to_table: :operational_events }, null: true

    add_index :holds, :placed_for_operational_event_id,
      where: "status = 'active' AND placed_for_operational_event_id IS NOT NULL",
      name: "index_holds_on_placed_for_oe_id_active"
  end
end
