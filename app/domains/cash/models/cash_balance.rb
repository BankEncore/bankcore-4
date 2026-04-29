# frozen_string_literal: true

module Cash
  module Models
    class CashBalance < ApplicationRecord
      self.table_name = "cash_balances"

      belongs_to :cash_location, class_name: "Cash::Models::CashLocation"
      belongs_to :last_cash_movement, class_name: "Cash::Models::CashMovement", optional: true
      belongs_to :last_cash_count, class_name: "Cash::Models::CashCount", optional: true

      validates :currency, inclusion: { in: %w[USD] }
      validates :amount_minor_units, numericality: { only_integer: true }
    end
  end
end
