# frozen_string_literal: true

module Cash
  module Commands
    class ApproveCashVariance
      class Error < StandardError; end
      class NotFound < Error; end
      class InvalidState < Error; end

      def self.call(cash_variance_id:, approving_actor_id:)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: approving_actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_VARIANCE_APPROVE,
          scope: nil
        )

        Cash::Models::CashVariance.transaction do
          variance = Cash::Models::CashVariance.lock.find_by(id: cash_variance_id)
          raise NotFound, "cash_variance_id=#{cash_variance_id}" if variance.nil?
          return variance if variance.status == Cash::Models::CashVariance::STATUS_POSTED
          unless variance.status == Cash::Models::CashVariance::STATUS_PENDING_APPROVAL ||
              variance.status == Cash::Models::CashVariance::STATUS_APPROVED
            raise InvalidState, "variance must be pending_approval or approved, was #{variance.status.inspect}"
          end
          if variance.actor_id.to_i == approving_actor_id.to_i
            raise InvalidState, "approver must not be the count actor"
          end

          variance.update!(
            status: Cash::Models::CashVariance::STATUS_APPROVED,
            approving_actor_id: approving_actor_id,
            approved_at: variance.approved_at || Time.current
          )
          post_variance!(variance, approving_actor_id)
        end
      rescue Workspace::Authorization::Forbidden => e
        raise InvalidState, e.message
      end

      def self.post_variance!(variance, approving_actor_id)
        return variance if variance.cash_variance_posted_event_id.present?

        result = Core::OperationalEvents::Commands::RecordEvent.call(
          event_type: "cash.variance.posted",
          channel: "system",
          idempotency_key: "cash-variance-posted:#{variance.id}",
          amount_minor_units: variance.amount_minor_units,
          currency: variance.currency,
          actor_id: approving_actor_id,
          operating_unit_id: variance.operating_unit_id,
          reference_id: variance.id.to_s
        )
        Core::Posting::Commands::PostEvent.call(operational_event_id: result.fetch(:event).id)
        variance.update!(
          status: Cash::Models::CashVariance::STATUS_POSTED,
          cash_variance_posted_event: result.fetch(:event),
          posted_at: Time.current
        )
        variance
      end
      private_class_method :post_variance!
    end
  end
end
