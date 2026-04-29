# frozen_string_literal: true

require "digest"

module Cash
  module Commands
    class RecordCashCount
      class Error < StandardError; end
      class InvalidRequest < Error; end
      class MismatchedIdempotency < Error; end

      def self.call(cash_location_id:, counted_amount_minor_units:, actor_id:, idempotency_key:,
        expected_amount_minor_units: nil, currency: "USD", business_date: nil, channel: "branch")
        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)

        location = Cash::Models::CashLocation.lock.find_by(id: cash_location_id)
        raise InvalidRequest, "cash_location_id not found" if location.nil?
        raise InvalidRequest, "cash location must be active" unless location.active?
        raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"

        expected = expected_amount_minor_units
        expected = Cash::Services::BalanceProjector.balance_for(location).amount_minor_units if expected.nil?
        fp = fingerprint(location.id, counted_amount_minor_units, expected, actor_id, currency, on_date)

        Cash::Models::CashCount.transaction do
          existing = Cash::Models::CashCount.lock.find_by(idempotency_key: idempotency_key)
          return existing if existing && existing.request_fingerprint == fp
          raise MismatchedIdempotency, "idempotency replay does not match original count" if existing

          count = Cash::Models::CashCount.create!(
            cash_location: location,
            operating_unit: location.operating_unit,
            actor_id: actor_id,
            counted_amount_minor_units: counted_amount_minor_units,
            expected_amount_minor_units: expected,
            currency: currency,
            business_date: on_date,
            idempotency_key: idempotency_key,
            request_fingerprint: fp
          )

          Cash::Services::BalanceProjector.apply_count!(count)
          event = record_event!(count, channel)
          count.update!(operational_event: event)
          create_variance!(count)
          count
        end
      rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
        raise InvalidRequest, e.message
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
      end

      def self.record_event!(count, channel)
        Cash::Services::PostOperationalEvent.call(
          event_type: "cash.count.recorded",
          channel: channel,
          idempotency_key: "cash-count-recorded:#{count.id}",
          reference_id: count.id.to_s,
          actor_id: count.actor_id,
          operating_unit_id: count.operating_unit_id,
          amount_minor_units: count.counted_amount_minor_units,
          currency: count.currency,
          business_date: count.business_date
        )
      end

      def self.create_variance!(count)
        variance = count.counted_amount_minor_units.to_i - count.expected_amount_minor_units.to_i
        return if variance.zero?

        Cash::Models::CashVariance.create!(
          cash_location: count.cash_location,
          cash_count: count,
          operating_unit: count.operating_unit,
          actor: count.actor,
          amount_minor_units: variance,
          currency: count.currency,
          business_date: count.business_date
        )
      end
      private_class_method :create_variance!

      def self.fingerprint(location_id, counted_amount_minor_units, expected_amount_minor_units, actor_id, currency, business_date)
        Digest::SHA256.hexdigest({
          cash_location_id: location_id.to_i,
          counted_amount_minor_units: counted_amount_minor_units.to_i,
          expected_amount_minor_units: expected_amount_minor_units.to_i,
          actor_id: actor_id.to_i,
          currency: currency.to_s,
          business_date: business_date.to_s
        }.to_json)
      end
      private_class_method :fingerprint
    end
  end
end
