# frozen_string_literal: true

class CreatePartyIndividualProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :party_individual_profiles do |t|
      t.bigint :party_record_id, null: false
      t.string :first_name, null: false
      t.string :middle_name
      t.string :last_name, null: false
      t.string :name_suffix
      t.string :preferred_first_name
      t.string :preferred_last_name
      t.date :date_of_birth
      t.string :occupation
      t.string :employer
      t.timestamps
    end

    add_foreign_key :party_individual_profiles, :party_records
    add_index :party_individual_profiles, :party_record_id, unique: true
  end
end
