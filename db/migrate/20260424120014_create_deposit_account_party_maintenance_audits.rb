# frozen_string_literal: true

class CreateDepositAccountPartyMaintenanceAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_account_party_maintenance_audits do |t|
      t.string :action, null: false
      t.string :channel, null: false
      t.string :idempotency_key, null: false
      t.date :business_date, null: false
      t.references :deposit_account, null: false, foreign_key: true
      t.references :party_record, null: false, foreign_key: true
      t.references :deposit_account_party, null: false, foreign_key: true, index: { name: "idx_dap_maintenance_audits_on_relationship_id" }
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.string :role, null: false
      t.date :effective_on, null: false
      t.date :ended_on
      t.timestamps
    end

    add_index :deposit_account_party_maintenance_audits,
      %i[channel idempotency_key],
      unique: true,
      name: "idx_dap_maintenance_audits_idempotency"
    add_check_constraint :deposit_account_party_maintenance_audits,
      "action IN ('authorized_signer.added','authorized_signer.ended')",
      name: "dap_maintenance_audits_action_check"
    add_check_constraint :deposit_account_party_maintenance_audits,
      "channel IN ('branch')",
      name: "dap_maintenance_audits_channel_check"
    add_check_constraint :deposit_account_party_maintenance_audits,
      "role = 'authorized_signer'",
      name: "dap_maintenance_audits_role_check"
  end
end
