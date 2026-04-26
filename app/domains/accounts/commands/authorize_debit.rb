# frozen_string_literal: true

module Accounts
  module Commands
    class AuthorizeDebit
      class Error < StandardError; end
      class InvalidRequest < Error; end

      DEBIT_EVENT_TYPES = %w[withdrawal.posted transfer.completed].freeze

      OUTCOME_DENIED = :nsf_denied
      OUTCOME_DENIED_REPLAY = :nsf_denied_replay

      def self.call(
        event_type:,
        channel:,
        idempotency_key:,
        amount_minor_units:,
        currency:,
        source_account_id:,
        destination_account_id: nil,
        business_date: nil,
        teller_session_id: nil,
        actor_id: nil,
        reference_id: nil
      )
        type = event_type.to_s
        raise InvalidRequest, "event_type not supported for debit authorization: #{event_type.inspect}" unless DEBIT_EVENT_TYPES.include?(type)

        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        existing = Core::OperationalEvents::Models::OperationalEvent.find_by(channel: channel, idempotency_key: idempotency_key)
        return replay_denial(existing, on_date) if existing&.event_type == "overdraft.nsf_denied"

        begin
          Core::OperationalEvents::Commands::RecordEvent.call(
            event_type: type,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: amount_minor_units,
            currency: currency,
            source_account_id: source_account_id,
            destination_account_id: destination_account_id,
            business_date: on_date,
            teller_session_id: teller_session_id,
            actor_id: actor_id,
            reference_id: reference_id
          )
        rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest => e
          raise unless e.message.match?(/insufficient available balance/i)

          handle_insufficient_available!(
            original_error: e,
            event_type: type,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: amount_minor_units,
            currency: currency,
            source_account_id: source_account_id,
            destination_account_id: destination_account_id,
            business_date: on_date,
            actor_id: actor_id
          )
        end
      end

      def self.handle_insufficient_available!(
        original_error:,
        event_type:,
        channel:,
        idempotency_key:,
        amount_minor_units:,
        currency:,
        source_account_id:,
        destination_account_id:,
        business_date:,
        actor_id:
      )
        source = Accounts::Models::DepositAccount.find_by(id: source_account_id)
        raise original_error if source.nil?

        policy = Products::Services::DepositProductResolver.call(
          deposit_account: source,
          as_of: business_date
        ).deny_nsf_policy
        raise original_error if policy.nil?

        denial_result = Core::OperationalEvents::Commands::RecordControlEvent.call(
          event_type: "overdraft.nsf_denied",
          channel: channel,
          idempotency_key: idempotency_key,
          reference_id: "attempt:#{event_type}",
          actor_id: actor_id,
          business_date: business_date,
          amount_minor_units: amount_minor_units,
          currency: currency,
          source_account_id: source_account_id,
          destination_account_id: destination_account_id
        )
        fee_event = record_and_post_nsf_fee!(policy, denial_result[:event], business_date)
        {
          outcome: denial_result[:outcome] == :replay ? OUTCOME_DENIED_REPLAY : OUTCOME_DENIED,
          denial_event: denial_result[:event],
          fee_event: fee_event
        }
      end
      private_class_method :handle_insufficient_available!

      def self.replay_denial(denial_event, business_date)
        fee_event = Core::OperationalEvents::Models::OperationalEvent.find_by(
          channel: "system",
          idempotency_key: nsf_fee_idempotency_key(denial_event)
        )
        unless fee_event
          policy = Products::Services::DepositProductResolver.call(
            deposit_account: denial_event.source_account,
            as_of: business_date
          ).deny_nsf_policy
          fee_event = record_and_post_nsf_fee!(policy, denial_event, business_date)
        end

        { outcome: OUTCOME_DENIED_REPLAY, denial_event: denial_event, fee_event: fee_event }
      end
      private_class_method :replay_denial

      def self.record_and_post_nsf_fee!(policy, denial_event, business_date)
        fee_idem = nsf_fee_idempotency_key(denial_event)
        begin
          record = Core::OperationalEvents::Commands::RecordEvent.call(
            event_type: "fee.assessed",
            channel: "system",
            idempotency_key: fee_idem,
            amount_minor_units: policy.nsf_fee_minor_units,
            currency: policy.currency,
            source_account_id: denial_event.source_account_id,
            business_date: business_date,
            reference_id: nsf_fee_reference_id(denial_event),
            force_nsf_fee: true
          )
          Core::Posting::Commands::PostEvent.call(operational_event_id: record[:event].id)
          record[:event].reload
        rescue Core::OperationalEvents::Commands::RecordEvent::PostedReplay
          existing = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: "system", idempotency_key: fee_idem)
          Core::Posting::Commands::PostEvent.call(operational_event_id: existing.id)
          existing.reload
        end
      end
      private_class_method :record_and_post_nsf_fee!

      def self.nsf_fee_idempotency_key(denial_event)
        "nsf-fee:#{denial_event.id}"
      end

      def self.nsf_fee_reference_id(denial_event)
        "nsf_denial:#{denial_event.id}"
      end
    end
  end
end
