# frozen_string_literal: true

module Branch
  module DashboardHelper
    def branch_session_time(value)
      return "Not recorded" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%d %H:%M")
    end

    def branch_money(value, signed: false)
      return "Not recorded" if value.nil?

      amount = value.to_i / 100.0
      formatted = number_to_currency(amount.abs, unit: "$", precision: 2)
      return formatted unless signed

      "#{amount.negative? ? '-' : '+'}#{formatted}"
    end
  end
end
