# frozen_string_literal: true

require "digest"

module Cash
  module Commands
    class ReceiveExternalCashShipment
      class Error < StandardError; end
      class InvalidRequest < Error; end
      class MismatchedIdempotency < Error; end

      def self.call(destination_cash_location_id:, amount_minor_units:, actor_id:, idempotency_key:,
        external_source:, shipment_reference:, currency: "USD", business_date: nil, channel: "branch")
        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)

        destination = Cash::Models::CashLocation.lock.find_by(id: destination_cash_location_id)
        raise InvalidRequest, "destination_cash_location_id not found" if destination.nil?

        external_source = normalize_required_string(external_source, "external_source")
        shipment_reference = normalize_required_string(shipment_reference, "shipment_reference")
        validate_destination!(destination, currency)
        authorize_actor!(actor_id, destination)

        fp = fingerprint(
          destination.id,
          amount_minor_units,
          actor_id,
          currency,
          on_date,
          external_source,
          shipment_reference
        )

        Cash::Models::CashMovement.transaction do
          existing = Cash::Models::CashMovement.lock.find_by(idempotency_key: idempotency_key)
          return existing if existing && existing.request_fingerprint == fp
          raise MismatchedIdempotency, "idempotency replay does not match original external cash shipment receipt" if existing

          movement = Cash::Models::CashMovement.create!(
            source_cash_location: nil,
            destination_cash_location: destination,
            operating_unit: destination.operating_unit,
            actor_id: actor_id,
            amount_minor_units: amount_minor_units,
            currency: currency,
            business_date: on_date,
            status: Cash::Models::CashMovement::STATUS_COMPLETED,
            movement_type: Cash::Models::CashMovement::TYPE_EXTERNAL_SHIPMENT_RECEIVED,
            external_source: external_source,
            shipment_reference: shipment_reference,
            idempotency_key: idempotency_key,
            request_fingerprint: fp,
            completed_at: Time.current
          )

          Cash::Services::BalanceProjector.apply_completed_movement!(movement)
          event = record_and_post_event!(movement, channel)
          movement.update!(operational_event: event)
          movement
        end
      rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate,
        Core::BusinessDate::Errors::NotSet,
        Workspace::Authorization::Forbidden,
        Core::OperationalEvents::Commands::RecordEvent::Error,
        Core::Posting::Commands::PostEvent::Error,
        ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
      end

      def self.validate_destination!(destination, currency)
        raise InvalidRequest, "destination cash location must be active" unless destination.active?
        raise InvalidRequest, "destination cash location must be a branch vault" unless destination.vault?
        raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"
      end
      private_class_method :validate_destination!

      def self.authorize_actor!(actor_id, destination)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_SHIPMENT_RECEIVE,
          scope: destination.operating_unit
        )
      end
      private_class_method :authorize_actor!

      def self.normalize_required_string(value, field_name)
        normalized = value.to_s.strip
        raise InvalidRequest, "#{field_name} is required" if normalized.blank?

        normalized
      end
      private_class_method :normalize_required_string

      def self.record_and_post_event!(movement, channel)
        result = Core::OperationalEvents::Commands::RecordEvent.call(
          event_type: "cash.shipment.received",
          channel: channel,
          idempotency_key: "cash-shipment-received:#{movement.id}",
          amount_minor_units: movement.amount_minor_units,
          currency: movement.currency,
          actor_id: movement.actor_id,
          operating_unit_id: movement.operating_unit_id,
          reference_id: movement.id.to_s
        )
        Core::Posting::Commands::PostEvent.call(operational_event_id: result.fetch(:event).id)
        result.fetch(:event).reload
      end
      private_class_method :record_and_post_event!

      def self.fingerprint(destination_id, amount_minor_units, actor_id, currency, business_date, external_source, shipment_reference)
        Digest::SHA256.hexdigest({
          destination_cash_location_id: destination_id.to_i,
          amount_minor_units: amount_minor_units.to_i,
          actor_id: actor_id.to_i,
          currency: currency.to_s,
          business_date: business_date.to_s,
          external_source: external_source.to_s,
          shipment_reference: shipment_reference.to_s
        }.to_json)
      end
      private_class_method :fingerprint
    end
  end
end
