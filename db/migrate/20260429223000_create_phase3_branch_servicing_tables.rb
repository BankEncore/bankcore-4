# frozen_string_literal: true

class CreatePhase3BranchServicingTables < ActiveRecord::Migration[8.1]
  RESTRICTION_TYPES = %w[debit_block full_freeze close_block watch_only].freeze
  RESTRICTION_STATUSES = %w[active released].freeze
  LIFECYCLE_ACTIONS = %w[closed].freeze
  CONTACT_STATUSES = %w[active inactive].freeze
  EMAIL_PURPOSES = %w[primary secondary].freeze
  PHONE_PURPOSES = %w[mobile home work].freeze
  ADDRESS_PURPOSES = %w[residential mailing].freeze
  CONTACT_AUDIT_ACTIONS = %w[added ended superseded].freeze

  def change
    create_table :account_restrictions do |t|
      t.references :deposit_account, null: false, foreign_key: true
      t.string :restriction_type, null: false
      t.string :status, null: false, default: "active"
      t.string :channel, null: false
      t.string :idempotency_key, null: false
      t.date :business_date, null: false
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.references :released_by_actor, null: true, foreign_key: { to_table: :operators }
      t.references :restricted_operational_event, null: true, foreign_key: { to_table: :operational_events },
        index: { unique: true, name: "idx_account_restrictions_restricted_event" }
      t.references :unrestricted_operational_event, null: true, foreign_key: { to_table: :operational_events },
        index: { unique: true, name: "idx_account_restrictions_unrestricted_event" }
      t.string :reason_code, null: false
      t.text :reason_description
      t.date :effective_on, null: false
      t.date :released_on
      t.string :release_idempotency_key
      t.timestamps
    end

    add_check_constraint :account_restrictions, in_list_sql("restriction_type", RESTRICTION_TYPES),
      name: "account_restrictions_type_check"
    add_check_constraint :account_restrictions, in_list_sql("status", RESTRICTION_STATUSES),
      name: "account_restrictions_status_check"
    add_check_constraint :account_restrictions, "channel = 'branch'", name: "account_restrictions_channel_check"
    add_check_constraint :account_restrictions,
      "status <> 'released' OR (released_on IS NOT NULL AND released_by_actor_id IS NOT NULL)",
      name: "account_restrictions_release_fields_check"
    add_index :account_restrictions, [ :channel, :idempotency_key ], unique: true
    add_index :account_restrictions, :release_idempotency_key, unique: true
    add_index :account_restrictions, [ :deposit_account_id, :status, :restriction_type ],
      name: "idx_account_restrictions_account_status_type"

    create_table :account_lifecycle_events do |t|
      t.references :deposit_account, null: false, foreign_key: true
      t.string :action, null: false
      t.string :channel, null: false
      t.string :idempotency_key, null: false
      t.date :business_date, null: false
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.references :operational_event, null: true, foreign_key: true,
        index: { unique: true, name: "idx_account_lifecycle_events_operational_event" }
      t.string :reason_code, null: false
      t.text :reason_description
      t.date :effective_on, null: false
      t.timestamps
    end

    add_check_constraint :account_lifecycle_events, in_list_sql("action", LIFECYCLE_ACTIONS),
      name: "account_lifecycle_events_action_check"
    add_check_constraint :account_lifecycle_events, "channel = 'branch'", name: "account_lifecycle_events_channel_check"
    add_index :account_lifecycle_events, [ :channel, :idempotency_key ], unique: true
    add_index :account_lifecycle_events, [ :deposit_account_id, :action, :business_date ],
      name: "idx_account_lifecycle_events_account_action_date"

    create_table :party_emails do |t|
      t.references :party_record, null: false, foreign_key: true
      t.string :email, null: false
      t.string :purpose, null: false
      t.string :status, null: false, default: "active"
      t.date :effective_on, null: false
      t.date :ended_on
      t.timestamps
    end

    add_check_constraint :party_emails, in_list_sql("purpose", EMAIL_PURPOSES), name: "party_emails_purpose_check"
    add_check_constraint :party_emails, in_list_sql("status", CONTACT_STATUSES), name: "party_emails_status_check"
    add_index :party_emails, [ :party_record_id, :status, :purpose ]

    create_table :party_phones do |t|
      t.references :party_record, null: false, foreign_key: true
      t.string :phone_number, null: false
      t.string :purpose, null: false
      t.string :status, null: false, default: "active"
      t.date :effective_on, null: false
      t.date :ended_on
      t.timestamps
    end

    add_check_constraint :party_phones, in_list_sql("purpose", PHONE_PURPOSES), name: "party_phones_purpose_check"
    add_check_constraint :party_phones, in_list_sql("status", CONTACT_STATUSES), name: "party_phones_status_check"
    add_index :party_phones, [ :party_record_id, :status, :purpose ]

    create_table :party_addresses do |t|
      t.references :party_record, null: false, foreign_key: true
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :region, null: false
      t.string :postal_code, null: false
      t.string :country, null: false, default: "US"
      t.string :purpose, null: false
      t.string :status, null: false, default: "active"
      t.date :effective_on, null: false
      t.date :ended_on
      t.timestamps
    end

    add_check_constraint :party_addresses, in_list_sql("purpose", ADDRESS_PURPOSES),
      name: "party_addresses_purpose_check"
    add_check_constraint :party_addresses, in_list_sql("status", CONTACT_STATUSES),
      name: "party_addresses_status_check"
    add_index :party_addresses, [ :party_record_id, :status, :purpose ]

    create_table :party_contact_audits do |t|
      t.references :party_record, null: false, foreign_key: true
      t.string :contact_table, null: false
      t.bigint :contact_id, null: false
      t.string :action, null: false
      t.string :channel, null: false
      t.string :idempotency_key, null: false
      t.date :business_date, null: false
      t.references :actor, null: false, foreign_key: { to_table: :operators }
      t.text :old_summary
      t.text :new_summary
      t.timestamps
    end

    add_check_constraint :party_contact_audits, "contact_table IN ('party_emails', 'party_phones', 'party_addresses')",
      name: "party_contact_audits_contact_table_check"
    add_check_constraint :party_contact_audits, in_list_sql("action", CONTACT_AUDIT_ACTIONS),
      name: "party_contact_audits_action_check"
    add_check_constraint :party_contact_audits, "channel = 'branch'", name: "party_contact_audits_channel_check"
    add_index :party_contact_audits, [ :channel, :idempotency_key ], unique: true
    add_index :party_contact_audits, [ :party_record_id, :created_at ]
  end

  private

  def in_list_sql(column_name, values)
    quoted = values.map { |value| connection.quote(value) }.join(", ")
    "#{column_name} IN (#{quoted})"
  end
end
