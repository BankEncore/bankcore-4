# frozen_string_literal: true

module Admin
  class DepositProductFeeRulesController < ApplicationController
    def index
      @as_of = parse_optional_date_param(:as_of)
      @deposit_product_id = params[:deposit_product_id].presence
      @fee_rules = if @error_message.present?
        Products::Models::DepositProductFeeRule.none
      elsif @as_of
        Products::Queries::ActiveFeeRules.monthly_maintenance(
          business_date: @as_of,
          deposit_product_id: @deposit_product_id
        )
      else
        raw_scope
      end
    end

    private

    def raw_scope
      scope = Products::Models::DepositProductFeeRule.includes(:deposit_product).order(:deposit_product_id, :effective_on, :id)
      scope = scope.where(deposit_product_id: @deposit_product_id) if @deposit_product_id.present?
      scope
    end
  end
end
