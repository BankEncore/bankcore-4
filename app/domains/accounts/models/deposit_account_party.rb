# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccountParty < ApplicationRecord
      self.table_name = "deposit_account_parties"

      ROLE_OWNER = "owner"
      ROLE_JOINT_OWNER = "joint_owner"
      ROLE_AUTHORIZED_SIGNER = "authorized_signer"
      ROLES = [
        ROLE_OWNER,
        ROLE_JOINT_OWNER,
        ROLE_AUTHORIZED_SIGNER,
        "beneficiary",
        "trustee",
        "custodian",
        "other"
      ].freeze
      STATUS_ACTIVE = "active"
      STATUS_PENDING = "pending"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_PENDING, STATUS_INACTIVE ].freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :party_record, class_name: "Party::Models::PartyRecord"

      validates :role, presence: true, inclusion: { in: ROLES }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :effective_on, presence: true
    end
  end
end
