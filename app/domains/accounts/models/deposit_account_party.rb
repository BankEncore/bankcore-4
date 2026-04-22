# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccountParty < ApplicationRecord
      self.table_name = "deposit_account_parties"

      ROLE_OWNER = "owner"
      STATUS_ACTIVE = "active"
      STATUS_PENDING = "pending"
      STATUS_INACTIVE = "inactive"

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :party_record, class_name: "Party::Models::PartyRecord"

      validates :role, presence: true
      validates :status, presence: true
      validates :effective_on, presence: true
    end
  end
end
