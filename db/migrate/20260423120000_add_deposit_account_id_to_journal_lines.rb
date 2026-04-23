# frozen_string_literal: true

class AddDepositAccountIdToJournalLines < ActiveRecord::Migration[8.1]
  def change
    add_reference :journal_lines, :deposit_account, foreign_key: { to_table: :deposit_accounts }, null: true
  end
end
