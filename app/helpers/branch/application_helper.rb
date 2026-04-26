# frozen_string_literal: true

module Branch
  module ApplicationHelper
    def branch_money(value, signed: false)
      return "Not recorded" if value.nil?

      amount = value.to_i / 100.0
      formatted = number_to_currency(amount.abs, unit: "$", precision: 2)
      return formatted unless signed

      "#{amount.negative? ? '-' : '+'}#{formatted}"
    end

    def branch_date(value)
      value&.to_date&.iso8601 || "Not recorded"
    end

    def branch_hold_type_options
      Accounts::Models::Hold::HOLD_TYPES.map { |value| [ value.humanize, value ] }
    end

    def branch_hold_reason_options
      Accounts::Models::Hold::REASON_CODES.map { |value| [ value.humanize, value ] }
    end
  end
end
