# frozen_string_literal: true

class CreateCoreBusinessDateCloseEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :core_business_date_close_events do |t|
      t.date :closed_on, null: false
      t.datetime :closed_at, null: false
      t.references :closed_by_operator, foreign_key: { to_table: :operators }, null: true
      t.timestamps
    end

    add_index :core_business_date_close_events, :closed_on, unique: true
  end
end
