# frozen_string_literal: true

class AddJournalEntriesBusinessDateIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :journal_entries, :business_date
  end
end
