# frozen_string_literal: true

module Admin
  module ApplicationHelper
    def admin_money(value)
      return "Not recorded" if value.nil?

      number_to_currency(value.to_i / 100.0, unit: "$", precision: 2)
    end

    def admin_date(value)
      return "Not recorded" if value.blank?

      value.iso8601
    end

    def admin_status_badge(value)
      classes = case value.to_s
      when "active"
        "bg-emerald-50 text-emerald-800 border-emerald-200"
      when "inactive"
        "bg-slate-50 text-slate-700 border-slate-200"
      else
        "bg-amber-50 text-amber-900 border-amber-200"
      end
      tag.span(value.to_s.humanize, class: "rounded border px-2 py-1 text-xs font-medium #{classes}")
    end

    def admin_product_label(product)
      return "Unknown product" if product.nil?

      "#{product.product_code} - #{product.name}"
    end

    def admin_rule_type(row)
      return row.fee_code if row.respond_to?(:fee_code)
      return row.mode if row.respond_to?(:mode)

      row.frequency
    end

    def admin_rule_value(row)
      return admin_money(row.amount_minor_units) if row.respond_to?(:amount_minor_units)
      return admin_money(row.nsf_fee_minor_units) if row.respond_to?(:nsf_fee_minor_units)

      "Cycle day #{row.cycle_day}"
    end

    def admin_filter_params
      params.permit(:deposit_product_id, :as_of).to_h.compact_blank
    end

    def admin_rule_kind_label(kind)
      case kind.to_s
      when "fee_rule"
        "Fee rule"
      when "overdraft_policy"
        "Overdraft policy"
      when "statement_profile"
        "Statement profile"
      else
        kind.to_s.humanize
      end
    end

    def admin_rule_kind_value_label(kind)
      case kind.to_s
      when "fee_rule"
        "Amount"
      when "overdraft_policy"
        "NSF fee"
      when "statement_profile"
        "Cycle day"
      else
        "Value"
      end
    end
  end
end
