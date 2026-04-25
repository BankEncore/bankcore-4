# frozen_string_literal: true

module Admin
  class DepositProductOverdraftPoliciesController < ApplicationController
    def index
      @as_of = parse_optional_date_param(:as_of)
      @deposit_product_id = params[:deposit_product_id].presence
      @overdraft_policies = if @error_message.present?
        Products::Models::DepositProductOverdraftPolicy.none
      elsif @as_of
        Products::Queries::ActiveOverdraftPolicies.deny_nsf(
          business_date: @as_of,
          deposit_product_id: @deposit_product_id
        )
      else
        raw_scope
      end
    end

    private

    def raw_scope
      scope = Products::Models::DepositProductOverdraftPolicy.includes(:deposit_product).order(:deposit_product_id, :effective_on, :id)
      scope = scope.where(deposit_product_id: @deposit_product_id) if @deposit_product_id.present?
      scope
    end
  end
end
