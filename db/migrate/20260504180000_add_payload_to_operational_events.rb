# frozen_string_literal: true

class AddPayloadToOperationalEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :operational_events, :payload, :jsonb
  end
end
