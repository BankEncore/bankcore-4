# frozen_string_literal: true

module Cash
  module Commands
    class ApproveCashMovement
      class Error < StandardError; end
      class NotFound < Error; end
      class InvalidState < Error; end

      def self.call(cash_movement_id:, approving_actor_id:, channel: "branch")
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: approving_actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE,
          scope: nil
        )

        Cash::Models::CashMovement.transaction do
          movement = Cash::Models::CashMovement.lock.find_by(id: cash_movement_id)
          raise NotFound, "cash_movement_id=#{cash_movement_id}" if movement.nil?
          return movement if movement.completed?
          unless movement.pending_approval?
            raise InvalidState, "movement must be pending_approval, was #{movement.status.inspect}"
          end
          if movement.actor_id.to_i == approving_actor_id.to_i
            raise InvalidState, "approver must not be the initiator"
          end

          movement.update!(
            status: Cash::Models::CashMovement::STATUS_COMPLETED,
            approving_actor_id: approving_actor_id,
            approved_at: Time.current,
            completed_at: Time.current
          )
          Cash::Services::BalanceProjector.apply_completed_movement!(movement)
          event = Cash::Commands::TransferCash.record_event!(movement, channel)
          movement.update!(operational_event: event)
          movement
        end
      rescue Workspace::Authorization::Forbidden => e
        raise InvalidState, e.message
      end
    end
  end
end
