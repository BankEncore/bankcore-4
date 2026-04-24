# frozen_string_literal: true

module Accounts
  module Commands
    class PlaceHold
      class Error < StandardError; end
      class InvalidRequest < Error; end

      # Creates an active hold and a posted `hold.placed` operational event (no GL posting).
      def self.call(deposit_account_id:, amount_minor_units:, currency:, channel:, idempotency_key:, business_date: nil)
        ch = channel.to_s
        unless Core::OperationalEvents::Commands::RecordEvent::CHANNELS.include?(ch)
          raise InvalidRequest, "channel must be one of: #{Core::OperationalEvents::Commands::RecordEvent::CHANNELS.join(", ")}"
        end

        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        begin
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
        rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
          raise InvalidRequest, e.message
        end
        validate_account!(deposit_account_id)
        validate_amount!(amount_minor_units, currency)

        begin
          Core::OperationalEvents::Models::OperationalEvent.transaction(requires_new: true) do
            existing = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(channel: channel, idempotency_key: idempotency_key)
            if existing
              validate_hold_placed_replay!(existing, deposit_account_id, amount_minor_units, currency)
              return { outcome: :replay, event: existing, hold: find_hold_for_event(existing) }
            end

            event = Core::OperationalEvents::Models::OperationalEvent.create!(
              event_type: "hold.placed",
              status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
              business_date: on_date,
              channel: channel,
              idempotency_key: idempotency_key,
              amount_minor_units: amount_minor_units,
              currency: currency,
              source_account_id: deposit_account_id
            )

            hold = Accounts::Models::Hold.create!(
              deposit_account_id: deposit_account_id,
              amount_minor_units: amount_minor_units,
              currency: currency,
              status: Accounts::Models::Hold::STATUS_ACTIVE,
              placed_by_operational_event: event
            )

            { outcome: :created, event: event, hold: hold }
          end
        rescue ActiveRecord::RecordNotUnique
          existing = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
          validate_hold_placed_replay!(existing, deposit_account_id, amount_minor_units, currency)
          { outcome: :replay, event: existing, hold: find_hold_for_event(existing) }
        end
      end

      def self.validate_hold_placed_replay!(existing, deposit_account_id, amount_minor_units, currency)
        raise InvalidRequest, "idempotency replay type mismatch" unless existing.event_type == "hold.placed"
        raise InvalidRequest, "idempotency replay mismatch" unless existing.source_account_id == deposit_account_id &&
          existing.amount_minor_units == amount_minor_units && existing.currency == currency
      end
      private_class_method :validate_hold_placed_replay!

      def self.find_hold_for_event(event)
        Accounts::Models::Hold.find_by(placed_by_operational_event_id: event.id)
      end
      private_class_method :find_hold_for_event

      def self.validate_account!(deposit_account_id)
        acc = Accounts::Models::DepositAccount.find_by(id: deposit_account_id)
        raise InvalidRequest, "deposit_account_id not found" if acc.nil?
        raise InvalidRequest, "account must be open" unless acc.status == Accounts::Models::DepositAccount::STATUS_OPEN
      end
      private_class_method :validate_account!

      def self.validate_amount!(amount_minor_units, currency)
        if amount_minor_units.nil? || amount_minor_units.to_i <= 0
          raise InvalidRequest, "amount_minor_units must be a positive integer"
        end
        raise InvalidRequest, "currency is required" if currency.blank?
        raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"
      end
      private_class_method :validate_amount!
    end
  end
end
