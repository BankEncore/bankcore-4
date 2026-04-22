# frozen_string_literal: true

class CreatePostingBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :posting_batches do |t|
      t.references :operational_event, null: false, foreign_key: true
      t.string :status, null: false

      t.timestamps
    end
  end
end
