# frozen_string_literal: true

class CreatePartyRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :party_records do |t|
      t.string :name, null: false
      t.string :party_type, null: false
      t.timestamps
    end
  end
end
