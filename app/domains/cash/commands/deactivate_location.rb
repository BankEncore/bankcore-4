# frozen_string_literal: true

module Cash
  module Commands
    class DeactivateLocation
      class InvalidRequest < StandardError; end

      def self.call(cash_location_id:)
        location = Models::CashLocation.includes(:cash_balance).find(cash_location_id)
        raise InvalidRequest, "cash balance must be zero before deactivation" unless zero_balance?(location)
        raise InvalidRequest, "open teller session references this location" if open_teller_session?(location)
        raise InvalidRequest, "pending cash movement references this location" if pending_movement?(location)
        raise InvalidRequest, "pending cash variance references this location" if pending_variance?(location)

        location.update!(status: Models::CashLocation::STATUS_INACTIVE)
        location
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end

      def self.zero_balance?(location)
        location.cash_balance.nil? || location.cash_balance.amount_minor_units.to_i.zero?
      end
      private_class_method :zero_balance?

      def self.open_teller_session?(location)
        Teller::Models::TellerSession.where(
          cash_location_id: location.id,
          status: Teller::Models::TellerSession::STATUS_OPEN
        ).exists?
      end
      private_class_method :open_teller_session?

      def self.pending_movement?(location)
        Models::CashMovement.where(status: Models::CashMovement::STATUS_PENDING_APPROVAL)
          .where("source_cash_location_id = :id OR destination_cash_location_id = :id", id: location.id)
          .exists?
      end
      private_class_method :pending_movement?

      def self.pending_variance?(location)
        Models::CashVariance.where(
          cash_location_id: location.id,
          status: Models::CashVariance::STATUS_PENDING_APPROVAL
        ).exists?
      end
      private_class_method :pending_variance?
    end
  end
end
