# frozen_string_literal: true

require "digest"

module Cash
  module Commands
    class TransferCash
      class Error < StandardError; end
      class InvalidRequest < Error; end
      class MismatchedIdempotency < Error; end

      def self.call(source_cash_location_id:, destination_cash_location_id:, amount_minor_units:, actor_id:,
        idempotency_key:, approval_actor_id: nil, currency: "USD", business_date: nil, channel: "branch",
        reason_code: nil)
        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)

        source = Cash::Models::CashLocation.lock.find_by(id: source_cash_location_id)
        destination = Cash::Models::CashLocation.lock.find_by(id: destination_cash_location_id)
        raise InvalidRequest, "source_cash_location_id not found" if source.nil?
        raise InvalidRequest, "destination_cash_location_id not found" if destination.nil?
        validate_locations!(source, destination, currency)
        authorize_actor!(actor_id, source.operating_unit)

        fp = fingerprint(source.id, destination.id, amount_minor_units, actor_id, approval_actor_id, currency, on_date, reason_code)

        Cash::Models::CashMovement.transaction do
          existing = Cash::Models::CashMovement.lock.find_by(idempotency_key: idempotency_key)
          return existing if existing && existing.request_fingerprint == fp
          raise MismatchedIdempotency, "idempotency replay does not match original transfer" if existing

          status = requires_approval?(source, destination, approval_actor_id) ?
            Cash::Models::CashMovement::STATUS_PENDING_APPROVAL :
            Cash::Models::CashMovement::STATUS_COMPLETED
          if status == Cash::Models::CashMovement::STATUS_COMPLETED && approval_actor_id.present?
            validate_approval!(actor_id, approval_actor_id)
            authorize_approval!(approval_actor_id, source.operating_unit)
          end

          movement = Cash::Models::CashMovement.create!(
            source_cash_location: source,
            destination_cash_location: destination,
            operating_unit: source.operating_unit,
            actor_id: actor_id,
            approving_actor_id: status == Cash::Models::CashMovement::STATUS_COMPLETED ? approval_actor_id : nil,
            amount_minor_units: amount_minor_units,
            currency: currency,
            business_date: on_date,
            status: status,
            movement_type: movement_type(source, destination),
            reason_code: reason_code,
            idempotency_key: idempotency_key,
            request_fingerprint: fp,
            approved_at: status == Cash::Models::CashMovement::STATUS_COMPLETED && approval_actor_id.present? ? Time.current : nil,
            completed_at: status == Cash::Models::CashMovement::STATUS_COMPLETED ? Time.current : nil
          )

          if movement.completed?
            Cash::Services::BalanceProjector.apply_completed_movement!(movement)
            event = record_event!(movement, channel)
            movement.update!(operational_event: event)
          end

          movement
        end
      rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
        raise InvalidRequest, e.message
      rescue Workspace::Authorization::Forbidden => e
        raise InvalidRequest, e.message
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
      end

      def self.requires_approval?(source, destination, approval_actor_id)
        return false if approval_actor_id.present?

        source.vault? || destination.vault?
      end
      private_class_method :requires_approval?

      def self.validate_locations!(source, destination, currency)
        raise InvalidRequest, "source and destination must be distinct" if source.id == destination.id
        raise InvalidRequest, "cash locations must be active" unless source.active? && destination.active?
        raise InvalidRequest, "cash locations must be in the same operating unit" unless source.operating_unit_id == destination.operating_unit_id
        raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"
      end
      private_class_method :validate_locations!

      def self.authorize_actor!(actor_id, operating_unit)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_CREATE,
          scope: operating_unit
        )
      end
      private_class_method :authorize_actor!

      def self.validate_approval!(actor_id, approval_actor_id)
        raise InvalidRequest, "approver must not be the initiator" if actor_id.to_i == approval_actor_id.to_i
      end
      private_class_method :validate_approval!

      def self.authorize_approval!(approval_actor_id, operating_unit)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: approval_actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE,
          scope: operating_unit
        )
      end
      private_class_method :authorize_approval!

      def self.movement_type(source, destination)
        if source.vault? && destination.teller_drawer?
          Cash::Models::CashMovement::TYPE_VAULT_TO_DRAWER
        elsif source.teller_drawer? && destination.vault?
          Cash::Models::CashMovement::TYPE_DRAWER_TO_VAULT
        else
          Cash::Models::CashMovement::TYPE_INTERNAL_TRANSFER
        end
      end
      private_class_method :movement_type

      def self.record_event!(movement, channel)
        Cash::Services::PostOperationalEvent.call(
          event_type: "cash.movement.completed",
          channel: channel,
          idempotency_key: "cash-movement-completed:#{movement.id}",
          reference_id: movement.id.to_s,
          actor_id: movement.actor_id,
          operating_unit_id: movement.operating_unit_id,
          amount_minor_units: movement.amount_minor_units,
          currency: movement.currency,
          business_date: movement.business_date
        )
      end

      def self.fingerprint(source_id, destination_id, amount_minor_units, actor_id, approval_actor_id, currency, business_date, reason_code)
        Digest::SHA256.hexdigest({
          source_cash_location_id: source_id.to_i,
          destination_cash_location_id: destination_id.to_i,
          amount_minor_units: amount_minor_units.to_i,
          actor_id: actor_id.to_i,
          approval_actor_id: approval_actor_id&.to_i,
          currency: currency.to_s,
          business_date: business_date.to_s,
          reason_code: reason_code.to_s
        }.to_json)
      end
      private_class_method :fingerprint
    end
  end
end
