# frozen_string_literal: true

class AddSupportSearchIndexesToOperationalEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :operational_events, %i[business_date id], name: "idx_oe_business_date_id"
    add_index :operational_events, %i[business_date status id], name: "idx_oe_business_date_status_id"
    add_index :operational_events, %i[business_date event_type id], name: "idx_oe_business_date_event_type_id"
    add_index :operational_events, %i[business_date channel id], name: "idx_oe_business_date_channel_id"
    add_index :operational_events, %i[actor_id business_date id],
      where: "actor_id IS NOT NULL",
      name: "idx_oe_actor_business_date_id"
    add_index :operational_events, %i[reference_id business_date id],
      where: "reference_id IS NOT NULL",
      name: "idx_oe_reference_business_date_id"
    add_index :operational_events, :idempotency_key, name: "idx_oe_idempotency_key"
  end
end
