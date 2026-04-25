# frozen_string_literal: true

module Admin
  class DepositProductStatementProfilesController < ApplicationController
    def index
      @as_of = parse_optional_date_param(:as_of)
      @deposit_product_id = params[:deposit_product_id].presence
      @statement_profiles = if @error_message.present?
        Products::Models::DepositProductStatementProfile.none
      elsif @as_of
        Products::Queries::ActiveStatementProfiles.monthly(
          business_date: @as_of,
          deposit_product_id: @deposit_product_id
        )
      else
        raw_scope
      end
    end

    private

    def raw_scope
      scope = Products::Models::DepositProductStatementProfile.includes(:deposit_product).order(:deposit_product_id, :effective_on, :id)
      scope = scope.where(deposit_product_id: @deposit_product_id) if @deposit_product_id.present?
      scope
    end
  end
end
