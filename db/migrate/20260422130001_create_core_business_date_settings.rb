# frozen_string_literal: true

class CreateCoreBusinessDateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :core_business_date_settings do |t|
      t.date :current_business_on, null: false
      t.timestamps
    end
  end
end
