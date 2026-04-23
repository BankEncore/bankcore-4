# frozen_string_literal: true

class AddSessionAndReferenceToOperationalEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :operational_events, :teller_session, null: true, foreign_key: true
    add_column :operational_events, :reference_id, :string
    add_column :operational_events, :actor_id, :bigint
  end
end
