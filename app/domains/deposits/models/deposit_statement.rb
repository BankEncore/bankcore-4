# frozen_string_literal: true

module Deposits
  module Models
    class DepositStatement < ApplicationRecord
      self.table_name = "deposit_statements"

      STATUS_GENERATED = "generated"
      STATUSES = [ STATUS_GENERATED ].freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :deposit_product_statement_profile, class_name: "Products::Models::DepositProductStatementProfile"

      validates :period_start_on, :period_end_on, :currency, :generated_on, :generated_at, :idempotency_key, presence: true
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :opening_ledger_balance_minor_units, :closing_ledger_balance_minor_units,
        numericality: { only_integer: true }
      validates :total_debits_minor_units, :total_credits_minor_units,
        numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validate :period_end_not_before_start
      validate :currency_matches_deposit_account

      private

      def period_end_not_before_start
        return if period_start_on.blank? || period_end_on.blank?
        return if period_end_on >= period_start_on

        errors.add(:period_end_on, "must be on or after period_start_on")
      end

      def currency_matches_deposit_account
        return if deposit_account.nil?
        return if currency == deposit_account.currency

        errors.add(:currency, "must match deposit account currency")
      end
    end
  end
end
