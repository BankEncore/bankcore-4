# frozen_string_literal: true

require "digest"

module Cash
  module Services
    module PostOperationalEvent
      module_function

      def call(event_type:, channel:, idempotency_key:, reference_id:, actor_id:, operating_unit_id:,
        amount_minor_units:, currency:, business_date:)
        incoming_fp = fingerprint(
          event_type: event_type,
          channel: channel,
          idempotency_key: idempotency_key,
          reference_id: reference_id,
          actor_id: actor_id,
          operating_unit_id: operating_unit_id,
          amount_minor_units: amount_minor_units,
          currency: currency
        )

        existing = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(
          channel: channel,
          idempotency_key: idempotency_key
        )
        return existing if existing && fingerprint_for(existing) == incoming_fp
        raise Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency.new(incoming_fp) if existing

        Core::OperationalEvents::Models::OperationalEvent.create!(
          event_type: event_type,
          status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
          business_date: business_date,
          channel: channel,
          idempotency_key: idempotency_key,
          reference_id: reference_id,
          actor_id: actor_id,
          operating_unit_id: operating_unit_id,
          amount_minor_units: amount_minor_units,
          currency: currency
        )
      end

      def fingerprint_for(event)
        fingerprint(
          event_type: event.event_type,
          channel: event.channel,
          idempotency_key: event.idempotency_key,
          reference_id: event.reference_id,
          actor_id: event.actor_id,
          operating_unit_id: event.operating_unit_id,
          amount_minor_units: event.amount_minor_units,
          currency: event.currency
        )
      end

      def fingerprint(event_type:, channel:, idempotency_key:, reference_id:, actor_id:, operating_unit_id:,
        amount_minor_units:, currency:)
        Digest::SHA256.hexdigest({
          event_type: event_type.to_s,
          channel: channel.to_s,
          idempotency_key: idempotency_key.to_s,
          reference_id: reference_id.to_s,
          actor_id: actor_id&.to_i,
          operating_unit_id: operating_unit_id&.to_i,
          amount_minor_units: amount_minor_units&.to_i,
          currency: currency.to_s
        }.to_json)
      end
    end
  end
end
