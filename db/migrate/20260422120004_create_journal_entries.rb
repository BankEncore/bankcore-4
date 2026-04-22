# frozen_string_literal: true

class CreateJournalEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_entries do |t|
      t.references :posting_batch, null: false, foreign_key: true
      t.references :operational_event, null: false, foreign_key: true
      t.date :business_date, null: false
      t.string :currency, null: false
      t.string :narrative
      t.datetime :effective_at, null: false
      t.string :status, null: false, default: "posted"
      t.references :reverses_journal_entry, foreign_key: { to_table: :journal_entries }
      t.bigint :reversing_journal_entry_id

      t.timestamps
    end

    add_foreign_key :journal_entries, :journal_entries, column: :reversing_journal_entry_id
    add_index :journal_entries, :reversing_journal_entry_id
  end
end
