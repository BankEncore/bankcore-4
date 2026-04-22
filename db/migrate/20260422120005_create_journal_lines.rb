# frozen_string_literal: true

class CreateJournalLines < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_lines do |t|
      t.references :journal_entry, null: false, foreign_key: true
      t.integer :sequence_no, null: false
      t.string :side, null: false
      t.references :gl_account, null: false, foreign_key: true
      t.bigint :amount_minor_units, null: false
      t.string :narrative

      t.timestamps
    end

    add_index :journal_lines, %i[journal_entry_id sequence_no], unique: true

    add_check_constraint :journal_lines, "amount_minor_units >= 0", name: "journal_lines_amount_non_negative"
    add_check_constraint :journal_lines, "side IN ('debit', 'credit')", name: "journal_lines_side_enum"
  end
end
