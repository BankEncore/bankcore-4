# frozen_string_literal: true

class AddSourceAccountIdToOperationalEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :operational_events, :source_account, foreign_key: { to_table: :deposit_accounts }, null: true
  end
end
