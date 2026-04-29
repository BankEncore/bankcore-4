# frozen_string_literal: true

module Cash
  module Queries
    module PendingCashApprovals
      module_function

      def call(operating_unit_id: nil)
        movements = Cash::Models::CashMovement
          .where(status: Cash::Models::CashMovement::STATUS_PENDING_APPROVAL)
          .includes(:source_cash_location, :destination_cash_location, :actor)
          .order(:business_date, :id)
        variances = Cash::Models::CashVariance
          .where(status: Cash::Models::CashVariance::STATUS_PENDING_APPROVAL)
          .includes(:cash_location, :cash_count, :actor)
          .order(:business_date, :id)

        if operating_unit_id.present?
          movements = movements.where(operating_unit_id: operating_unit_id)
          variances = variances.where(operating_unit_id: operating_unit_id)
        end

        { movements: movements.to_a, variances: variances.to_a }
      end
    end
  end
end
