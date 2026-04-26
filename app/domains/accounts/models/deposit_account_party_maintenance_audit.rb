# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccountPartyMaintenanceAudit < ApplicationRecord
      self.table_name = "deposit_account_party_maintenance_audits"

      ACTION_AUTHORIZED_SIGNER_ADDED = "authorized_signer.added"
      ACTION_AUTHORIZED_SIGNER_ENDED = "authorized_signer.ended"
      ACTIONS = [ ACTION_AUTHORIZED_SIGNER_ADDED, ACTION_AUTHORIZED_SIGNER_ENDED ].freeze
      CHANNELS = [ "branch" ].freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :party_record, class_name: "Party::Models::PartyRecord"
      belongs_to :deposit_account_party, class_name: "Accounts::Models::DepositAccountParty"
      belongs_to :actor, class_name: "Workspace::Models::Operator"

      validates :action, presence: true, inclusion: { in: ACTIONS }
      validates :channel, presence: true, inclusion: { in: CHANNELS }
      validates :idempotency_key, presence: true
      validates :business_date, presence: true
      validates :role, presence: true, inclusion: { in: [ Accounts::Models::DepositAccountParty::ROLE_AUTHORIZED_SIGNER ] }
      validates :effective_on, presence: true
    end
  end
end
