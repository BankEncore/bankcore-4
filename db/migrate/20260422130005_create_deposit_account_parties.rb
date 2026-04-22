# frozen_string_literal: true

class CreateDepositAccountParties < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_account_parties do |t|
      t.bigint :deposit_account_id, null: false
      t.bigint :party_record_id, null: false
      t.string :role, null: false
      t.string :status, null: false
      t.date :effective_on, null: false
      t.date :ended_on
      t.timestamps
    end

    add_foreign_key :deposit_account_parties, :deposit_accounts
    add_foreign_key :deposit_account_parties, :party_records
    add_index :deposit_account_parties, :deposit_account_id
    add_index :deposit_account_parties, :party_record_id
    add_index :deposit_account_parties,
      %i[deposit_account_id party_record_id role],
      unique: true,
      name: "index_dap_unique_open_active_per_account_party_role",
      where: "status = 'active' AND ended_on IS NULL"
  end
end
