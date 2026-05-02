# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccountNumberAllocation < ApplicationRecord
      self.table_name = "deposit_account_number_allocations"

      GLOBAL_KEY = "global"
      MAX_SEQUENCE = 999_999

      validates :allocation_key, presence: true, uniqueness: true
      validates :last_sequence, numericality: {
        only_integer: true,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: MAX_SEQUENCE
      }
    end
  end
end
