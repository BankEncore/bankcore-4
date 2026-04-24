# frozen_string_literal: true

module Accounts
  module Commands
    class PlaceHold
      class Error < StandardError; end
      class InvalidRequest < Error; end

      # Creates an active hold and a posted `hold.placed` operational event (no GL posting).
      def self.call(deposit_account_id:, amount_minor_units:, currency:, channel:, idempotency_key:, business_date: nil,
                    placed_for_operational_event_id: nil)
        ch = channel.to_s
        unless Core::OperationalEvents::Commands::RecordEvent::CHANNELS.include?(ch)
          raise InvalidRequest, "channel must be one of: #{Core::OperationalEvents::Commands::RecordEvent::CHANNELS.join(", ")}"
        end

        placed_for_id = normalize_placed_for_operational_event_id(placed_for_operational_event_id)

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
            existing = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(channel: ch, idempotency_key: idempotency_key)
            if existing
              validate_hold_placed_replay!(existing, deposit_account_id, amount_minor_units, currency, placed_for_id)
              return { outcome: :replay, event: existing, hold: find_hold_for_event(existing) }
            end

            if placed_for_id
              deposit_oe = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(id: placed_for_id)
              validate_deposit_link!(deposit_oe, deposit_account_id, amount_minor_units, currency.to_s)
            end

            event = Core::OperationalEvents::Models::OperationalEvent.create!(
              event_type: "hold.placed",
              status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
              business_date: on_date,
              channel: ch,
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
              placed_by_operational_event: event,
              placed_for_operational_event_id: placed_for_id
            )

            { outcome: :created, event: event, hold: hold }
          end
        rescue ActiveRecord::RecordNotUnique
          existing = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: ch, idempotency_key: idempotency_key)
          validate_hold_placed_replay!(existing, deposit_account_id, amount_minor_units, currency, placed_for_id)
          { outcome: :replay, event: existing, hold: find_hold_for_event(existing) }
        end
      end

      def self.normalize_placed_for_operational_event_id(value)
        return nil if value.blank?

        value.to_i
      end
      private_class_method :normalize_placed_for_operational_event_id

      def self.validate_hold_placed_replay!(existing, deposit_account_id, amount_minor_units, currency, placed_for_operational_event_id)
        raise InvalidRequest, "idempotency replay type mismatch" unless existing.event_type == "hold.placed"
        raise InvalidRequest, "idempotency replay mismatch" unless existing.source_account_id == deposit_account_id &&
          existing.amount_minor_units == amount_minor_units && existing.currency == currency

        hold = find_hold_for_event(existing)
        raise InvalidRequest, "idempotency replay mismatch" if hold.nil?

        actual_ref = hold.placed_for_operational_event_id
        if (placed_for_operational_event_id.nil? && !actual_ref.nil?) ||
            (!placed_for_operational_event_id.nil? && actual_ref != placed_for_operational_event_id)
          raise InvalidRequest, "idempotency replay mismatch for placed_for_operational_event_id"
        end
      end
      private_class_method :validate_hold_placed_replay!

      def self.validate_deposit_link!(deposit_oe, deposit_account_id, amount_minor_units, currency)
        raise InvalidRequest, "placed_for_operational_event_id not found" if deposit_oe.nil?
        unless deposit_oe.event_type == "deposit.accepted"
          raise InvalidRequest, "placed_for_operational_event must be deposit.accepted"
        end
        unless deposit_oe.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED
          raise InvalidRequest, "placed_for_operational_event must be posted"
        end
        unless deposit_oe.source_account_id == deposit_account_id
          raise InvalidRequest, "deposit account does not match deposit event source_account_id"
        end
        unless deposit_oe.currency.to_s == currency
          raise InvalidRequest, "currency must match deposit event"
        end

        held = Accounts::Models::Hold.where(
          placed_for_operational_event_id: deposit_oe.id,
          status: Accounts::Models::Hold::STATUS_ACTIVE
        ).sum(:amount_minor_units)

        if held + amount_minor_units.to_i > deposit_oe.amount_minor_units
          raise InvalidRequest, "active holds for this deposit cannot exceed the deposit amount"
        end
      end
      private_class_method :validate_deposit_link!

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
