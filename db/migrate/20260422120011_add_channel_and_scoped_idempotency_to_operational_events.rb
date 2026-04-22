# frozen_string_literal: true

class AddChannelAndScopedIdempotencyToOperationalEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :operational_events, :channel, :string, null: false, default: "legacy"
    remove_index :operational_events, name: "index_operational_events_on_idempotency_key"
    add_index :operational_events, %i[channel idempotency_key],
      unique: true,
      name: "index_operational_events_on_channel_and_idempotency_key"
    change_column_default :operational_events, :channel, from: "legacy", to: nil
  end

  def down
    change_column_default :operational_events, :channel, from: nil, to: "legacy"
    remove_index :operational_events, name: "index_operational_events_on_channel_and_idempotency_key"
    add_index :operational_events, :idempotency_key, unique: true, name: "index_operational_events_on_idempotency_key"
    remove_column :operational_events, :channel
  end
end
