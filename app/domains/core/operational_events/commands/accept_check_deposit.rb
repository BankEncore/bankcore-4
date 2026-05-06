# frozen_string_literal: true

module Core
  module OperationalEvents
    module Commands
      # Single outer transaction: RecordEvent → PostEvent → optional PlaceHold (ADR-0040).
      class AcceptCheckDeposit
        class Error < StandardError; end
        class InvalidRequest < Error; end

        # @return [Hash] keys: :operational_event, :record_outcome, :posting_outcome, :hold_outcome (optional), :hold (optional)
        def self.call(
          channel: "teller",
          idempotency_key:,
          amount_minor_units:,
          currency: "USD",
          source_account_id:,
          payload:,
          teller_session_id: nil,
          actor_id: nil,
          operating_unit_id: nil,
          business_date: nil,
          reference_id: nil,
          hold_amount_minor_units: nil,
          hold_idempotency_key: nil,
          hold_channel: nil,
          hold_type: nil,
          reason_code: nil,
          reason_description: nil,
          expires_on: nil
        )
          ch = channel.to_s
          hold_amt = hold_amount_minor_units.present? ? hold_amount_minor_units.to_i : 0

          if hold_amt.positive?
            raise InvalidRequest, "hold_idempotency_key is required when placing a hold" if hold_idempotency_key.blank?
            if hold_idempotency_key.to_s == idempotency_key.to_s
              raise InvalidRequest, "hold_idempotency_key must differ from deposit idempotency_key"
            end
          elsif hold_idempotency_key.present?
            raise InvalidRequest, "hold_amount_minor_units is required when hold_idempotency_key is present"
          end

          record_outcome = nil
          operational_event = nil
          posting_outcome = nil
          hold_outcome = nil
          hold = nil

          ActiveRecord::Base.transaction do
            begin
              rr = RecordEvent.call(
                event_type: RecordEvent::CHECK_DEPOSIT_ACCEPTED,
                channel: ch,
                idempotency_key: idempotency_key,
                amount_minor_units: amount_minor_units,
                currency: currency,
                source_account_id: source_account_id,
                teller_session_id: teller_session_id,
                actor_id: actor_id,
                operating_unit_id: operating_unit_id,
                business_date: business_date,
                reference_id: reference_id,
                payload: payload
              )
              operational_event = rr[:event]
              record_outcome = rr[:outcome]
            rescue RecordEvent::PostedReplay
              operational_event = Models::OperationalEvent.lock.find_by!(channel: ch, idempotency_key: idempotency_key)
              record_outcome = :replay
            end

            pr = Core::Posting::Commands::PostEvent.call(operational_event_id: operational_event.id)
            posting_outcome = pr[:outcome]
            operational_event = pr[:event]

            if hold_amt.positive?
              hold_ch = (hold_channel.presence || ch).to_s
              hr = Accounts::Commands::PlaceHold.call(
                deposit_account_id: source_account_id,
                amount_minor_units: hold_amt,
                currency: currency,
                channel: hold_ch,
                idempotency_key: hold_idempotency_key,
                business_date: business_date,
                placed_for_operational_event_id: operational_event.id,
                actor_id: actor_id,
                operating_unit_id: operating_unit_id,
                hold_type: hold_type,
                reason_code: reason_code,
                reason_description: reason_description,
                expires_on: expires_on
              )
              hold_outcome = hr[:outcome]
              hold = hr[:hold]
            end
          end

          out = {
            operational_event: operational_event,
            record_outcome: record_outcome,
            posting_outcome: posting_outcome
          }
          out[:hold_outcome] = hold_outcome if hold_amt.positive?
          out[:hold] = hold if hold
          out
        end
      end
    end
  end
end
