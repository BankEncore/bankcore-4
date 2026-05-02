# frozen_string_literal: true

class CreateDepositAccountNumberAllocations < ActiveRecord::Migration[8.1]
  GLOBAL_KEY = "global"
  MAX_SEQUENCE = 999_999

  def up
    create_table :deposit_account_number_allocations do |t|
      t.string :allocation_key, null: false
      t.integer :last_sequence, null: false, default: 0
      t.timestamps
    end

    add_index :deposit_account_number_allocations, :allocation_key, unique: true
    add_check_constraint :deposit_account_number_allocations,
      "last_sequence >= 0 AND last_sequence <= #{MAX_SEQUENCE}",
      name: "chk_deposit_account_number_allocations_sequence_range"

    backfill_deposit_account_numbers!

    add_check_constraint :deposit_accounts,
      "account_number ~ '^1[0-9]{11}$'",
      name: "chk_deposit_accounts_account_number_12_digits"
  end

  def down
    remove_check_constraint :deposit_accounts, name: "chk_deposit_accounts_account_number_12_digits"
    drop_table :deposit_account_number_allocations
  end

  private

  def backfill_deposit_account_numbers!
    sequence = 0

    select_all("SELECT id, created_at FROM deposit_accounts ORDER BY id").each do |row|
      sequence += 1
      raise "deposit account number sequence exhausted" if sequence > MAX_SEQUENCE

      created_on = row.fetch("created_at")&.to_date || Date.current
      account_number = account_number_for(on_date: created_on, sequence: sequence)
      execute <<~SQL.squish
        UPDATE deposit_accounts
        SET account_number = #{quote(account_number)}
        WHERE id = #{row.fetch("id").to_i}
      SQL
    end

    execute <<~SQL.squish
      INSERT INTO deposit_account_number_allocations (allocation_key, last_sequence, created_at, updated_at)
      VALUES (#{quote(GLOBAL_KEY)}, #{sequence}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def account_number_for(on_date:, sequence:)
    base = "1#{on_date.strftime("%y%m")}#{sequence.to_s.rjust(6, "0")}"
    "#{base}#{luhn_check_digit(base)}"
  end

  def luhn_check_digit(base)
    sum = base.reverse.chars.each_with_index.sum do |char, index|
      digit = char.to_i
      if index.even?
        doubled = digit * 2
        doubled > 9 ? doubled - 9 : doubled
      else
        digit
      end
    end

    (10 - (sum % 10)) % 10
  end
end
