# frozen_string_literal: true

module Ops
  module ApplicationHelper
    def ops_money(value, signed: false)
      return "Not recorded" if value.nil?

      amount = value.to_i / 100.0
      formatted = number_to_currency(amount.abs, unit: "$", precision: 2)
      return formatted unless signed

      "#{amount.negative? ? '-' : '+'}#{formatted}"
    end

    def ops_time(value)
      return "Not recorded" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%d %H:%M")
    end

    def ops_status_badge(value)
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

    def ops_account_label(account)
      return "None" if account.nil?

      product = account.deposit_product&.name.presence || account.product_code
      [ "##{account.id}", account.account_number, product ].compact.join(" - ")
    end

    def ops_event_amount(event)
      amount = ops_money(event.amount_minor_units)
      return amount if event.currency.blank?

      "#{amount} #{event.currency}"
    end
  end
end
