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

    def branch_status_badge(value)
      classes = case value.to_s
      when "posted", "closed", "true"
        "bg-emerald-50 text-emerald-800 border-emerald-200"
      when "pending", "pending_supervisor", "false"
        "bg-amber-50 text-amber-900 border-amber-200"
      else
        "bg-slate-50 text-slate-700 border-slate-200"
      end
      tag.span(value.to_s.humanize, class: "rounded border px-2 py-1 text-xs font-medium #{classes}")
    end

    def branch_event_type_badge(value)
      event_type = value.to_s
      classes = case event_type
      when /\A(deposit|withdrawal|transfer|ach|interest)\./
        "bg-blue-50 text-blue-800 border-blue-200"
      when /\A(fee|overdraft)\./
        "bg-violet-50 text-violet-800 border-violet-200"
      when /\A(hold|posting)\./
        "bg-amber-50 text-amber-900 border-amber-200"
      else
        "bg-slate-50 text-slate-700 border-slate-200"
      end

      tag.span(event_type.presence || "Unknown", class: "rounded border px-2 py-1 text-xs font-medium #{classes}")
    end
  end
end
