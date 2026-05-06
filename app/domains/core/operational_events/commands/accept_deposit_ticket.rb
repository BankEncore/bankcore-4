# frozen_string_literal: true

module Core
  module OperationalEvents
    module Commands
      # Orchestrates one teller deposit ticket while preserving cash/check event semantics (ADR-0043).
      class AcceptDepositTicket
        class Error < StandardError; end
        class InvalidRequest < Error; end

        # @return [Hash] keys: :ticket_reference, :cash_result, :check_result, :hold, :hold_outcome
        def self.call(
          channel: "teller",
          idempotency_key:,
          source_account_id:,
          currency: "USD",
          teller_session_id: nil,
          actor_id: nil,
          operating_unit_id: nil,
          business_date: nil,
          cash_amount_minor_units: nil,
          check_amount_minor_units: nil,
          check_payload: nil,
          hold_amount_minor_units: nil,
          hold_idempotency_key: nil,
          hold_expires_on: nil,
          reference_id: nil
        )
          cash_amount = normalize_optional_amount(cash_amount_minor_units)
          check_amount = normalize_optional_amount(check_amount_minor_units)
          hold_amount = normalize_optional_amount(hold_amount_minor_units)
          validate_presence!(cash_amount, check_amount)
          validate_check_payload!(check_amount, check_payload)
          validate_hold!(hold_amount, check_amount, hold_idempotency_key)

          ticket_reference = reference_id.presence || "deposit-ticket:#{idempotency_key}"
          cash_result = nil
          check_result = nil

          ActiveRecord::Base.transaction do
            cash_result = accept_cash!(
              channel: channel,
              idempotency_key: "#{idempotency_key}:cash",
              amount_minor_units: cash_amount,
              currency: currency,
              source_account_id: source_account_id,
              teller_session_id: teller_session_id,
              actor_id: actor_id,
              operating_unit_id: operating_unit_id,
              business_date: business_date,
              reference_id: ticket_reference
            ) if cash_amount.positive?

            if check_amount.positive?
              check_result = AcceptCheckDeposit.call(
                channel: channel,
                idempotency_key: "#{idempotency_key}:checks",
                amount_minor_units: check_amount,
                currency: currency,
                source_account_id: source_account_id,
                teller_session_id: teller_session_id,
                actor_id: actor_id,
                operating_unit_id: operating_unit_id,
                business_date: business_date,
                reference_id: ticket_reference,
                payload: check_payload,
                hold_amount_minor_units: hold_amount,
                hold_idempotency_key: resolved_hold_idempotency_key(idempotency_key, hold_amount, hold_idempotency_key),
                expires_on: hold_expires_on
              )
            end
          end

          out = {
            ticket_reference: ticket_reference
          }
          out[:cash_result] = cash_result if cash_result
          out[:check_result] = check_result if check_result
          if check_result&.key?(:hold_outcome)
            out[:hold_outcome] = check_result[:hold_outcome]
            out[:hold] = check_result[:hold]
          end
          out
        rescue RecordEvent::InvalidRequest,
          RecordEvent::MismatchedIdempotency,
          Core::Posting::Commands::PostEvent::InvalidState,
          Accounts::Commands::PlaceHold::InvalidRequest => e
          raise InvalidRequest, e.message
        end

        def self.normalize_optional_amount(value)
          return 0 if value.blank?

          value.to_i
        end
        private_class_method :normalize_optional_amount

        def self.validate_presence!(cash_amount, check_amount)
          return if cash_amount.positive? || check_amount.positive?

          raise InvalidRequest, "cash amount or check items are required"
        end
        private_class_method :validate_presence!

        def self.validate_check_payload!(check_amount, check_payload)
          return unless check_amount.positive?
          return if check_payload.present?

          raise InvalidRequest, "check payload is required when check amount is present"
        end
        private_class_method :validate_check_payload!

        def self.validate_hold!(hold_amount, check_amount, hold_idempotency_key)
          if hold_amount.positive?
            raise InvalidRequest, "check items are required when placing a check hold" unless check_amount.positive?
            raise InvalidRequest, "check hold amount cannot exceed check total" if hold_amount > check_amount
          elsif hold_idempotency_key.present?
            raise InvalidRequest, "hold amount is required when hold idempotency key is present"
          end
        end
        private_class_method :validate_hold!

        def self.resolved_hold_idempotency_key(idempotency_key, hold_amount, hold_idempotency_key)
          return nil unless hold_amount.positive?

          hold_idempotency_key.presence || "#{idempotency_key}:checks:hold"
        end
        private_class_method :resolved_hold_idempotency_key

        def self.accept_cash!(channel:, idempotency_key:, amount_minor_units:, currency:, source_account_id:,
                              teller_session_id:, actor_id:, operating_unit_id:, business_date:, reference_id:)
          record_outcome = nil
          event = nil

          begin
            result = RecordEvent.call(
              event_type: "deposit.accepted",
              channel: channel,
              idempotency_key: idempotency_key,
              amount_minor_units: amount_minor_units,
              currency: currency,
              source_account_id: source_account_id,
              teller_session_id: teller_session_id,
              actor_id: actor_id,
              operating_unit_id: operating_unit_id,
              business_date: business_date,
              reference_id: reference_id
            )
            event = result[:event]
            record_outcome = result[:outcome]
          rescue RecordEvent::PostedReplay
            event = Models::OperationalEvent.lock.find_by!(channel: channel, idempotency_key: idempotency_key)
            record_outcome = :replay
          end

          post = Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
          {
            operational_event: post[:event],
            record_outcome: record_outcome,
            posting_outcome: post[:outcome]
          }
        end
        private_class_method :accept_cash!
      end
    end
  end
end
