# frozen_string_literal: true

module Party
  module Models
    class PartyContactAudit < ApplicationRecord
      self.table_name = "party_contact_audits"

      ACTION_ADDED = "added"
      ACTION_ENDED = "ended"
      ACTION_SUPERSEDED = "superseded"
      ACTIONS = [ ACTION_ADDED, ACTION_ENDED, ACTION_SUPERSEDED ].freeze

      CONTACT_TABLES = %w[party_emails party_phones party_addresses].freeze

      belongs_to :party_record, class_name: "Party::Models::PartyRecord"
      belongs_to :actor, class_name: "Workspace::Models::Operator"

      validates :contact_table, presence: true, inclusion: { in: CONTACT_TABLES }
      validates :contact_id, :action, :channel, :idempotency_key, :business_date, presence: true
      validates :action, inclusion: { in: ACTIONS }
      validates :channel, inclusion: { in: [ "branch" ] }
    end
  end
end
