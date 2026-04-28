# frozen_string_literal: true

module Accounts
  module Commands
    class PlaceHold
      class Error < StandardError; end
      class InvalidRequest < Error; end

      # Creates an active hold and a posted `hold.placed` operational event (no GL posting).
      def self.call(deposit_account_id:, amount_minor_units:, currency:, channel:, idempotency_key:, business_date: nil,
                    placed_for_operational_event_id: nil, actor_id: nil, hold_type: nil, reason_code: nil,
                    reason_description: nil, expires_on: nil, operating_unit_id: nil)
        ch = channel.to_s
        unless Core::OperationalEvents::Commands::RecordEvent::CHANNELS.include?(ch)
          raise InvalidRequest, "channel must be one of: #{Core::OperationalEvents::Commands::RecordEvent::CHANNELS.join(", ")}"
        end

        placed_for_id = normalize_placed_for_operational_event_id(placed_for_operational_event_id)
        normalized_hold_type = normalize_hold_type(hold_type, placed_for_id)
        normalized_reason_code = normalize_reason_code(reason_code, normalized_hold_type)
        normalized_expires_on = normalize_expires_on(expires_on)

        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        begin
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
        rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
          raise InvalidRequest, e.message
        end
        validate_account!(deposit_account_id)
        validate_amount!(amount_minor_units, currency)
        validate_metadata!(normalized_hold_type, normalized_reason_code)
        validate_expiration!(normalized_expires_on, on_date)
        resolved_operating_unit = resolve_operating_unit(ch, actor_id, operating_unit_id)

        begin
          Core::OperationalEvents::Models::OperationalEvent.transaction(requires_new: true) do
            existing = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(channel: ch, idempotency_key: idempotency_key)
            if existing
              validate_hold_placed_replay!(
                existing,
                deposit_account_id,
                amount_minor_units,
                currency,
                placed_for_id,
                normalized_hold_type,
                normalized_reason_code,
                reason_description,
                normalized_expires_on,
                resolved_operating_unit&.id
              )
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
              source_account_id: deposit_account_id,
              actor_id: actor_id,
              operating_unit: resolved_operating_unit
            )

            hold = Accounts::Models::Hold.create!(
              deposit_account_id: deposit_account_id,
              amount_minor_units: amount_minor_units,
              currency: currency,
              status: Accounts::Models::Hold::STATUS_ACTIVE,
              placed_by_operational_event: event,
              placed_for_operational_event_id: placed_for_id,
              hold_type: normalized_hold_type,
              reason_code: normalized_reason_code,
              reason_description: reason_description.presence,
              expires_on: normalized_expires_on
            )

            { outcome: :created, event: event, hold: hold }
          end
        rescue ActiveRecord::RecordNotUnique
          existing = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: ch, idempotency_key: idempotency_key)
          validate_hold_placed_replay!(
            existing,
            deposit_account_id,
            amount_minor_units,
            currency,
            placed_for_id,
            normalized_hold_type,
            normalized_reason_code,
            reason_description,
            normalized_expires_on,
            resolved_operating_unit&.id
          )
          { outcome: :replay, event: existing, hold: find_hold_for_event(existing) }
        end
      end

      def self.normalize_placed_for_operational_event_id(value)
        return nil if value.blank?

        value.to_i
      end
      private_class_method :normalize_placed_for_operational_event_id

      def self.normalize_hold_type(value, placed_for_operational_event_id)
        return value.to_s if value.present?
        return Accounts::Models::Hold::HOLD_TYPE_DEPOSIT if placed_for_operational_event_id.present?

        Accounts::Models::Hold::HOLD_TYPE_ADMINISTRATIVE
      end
      private_class_method :normalize_hold_type

      def self.normalize_reason_code(value, hold_type)
        return value.to_s if value.present?
        return Accounts::Models::Hold::REASON_DEPOSIT_AVAILABILITY if hold_type == Accounts::Models::Hold::HOLD_TYPE_DEPOSIT

        Accounts::Models::Hold::REASON_MANUAL_REVIEW
      end
      private_class_method :normalize_reason_code

      def self.normalize_expires_on(value)
        return nil if value.blank?

        value.to_date
      rescue ArgumentError, TypeError, NoMethodError
        raise InvalidRequest, "expires_on must be a valid date"
      end
      private_class_method :normalize_expires_on

      def self.validate_hold_placed_replay!(
        existing,
        deposit_account_id,
        amount_minor_units,
        currency,
        placed_for_operational_event_id,
        hold_type,
        reason_code,
        reason_description,
        expires_on,
        operating_unit_id
      )
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
        unless hold.hold_type == hold_type &&
            hold.reason_code == reason_code &&
            hold.reason_description.to_s == reason_description.to_s &&
            hold.expires_on == expires_on &&
            existing.operating_unit_id == operating_unit_id
          raise InvalidRequest, "idempotency replay mismatch for hold metadata"
        end
      end
      private_class_method :validate_hold_placed_replay!

      def self.resolve_operating_unit(channel, actor_id, operating_unit_id)
        return nil unless %w[teller branch].include?(channel)

        actor = Workspace::Models::Operator.find_by(id: actor_id) if actor_id.present?
        Organization::Services::ResolveOperatingUnit.call(operator: actor, operating_unit_id: operating_unit_id)
      rescue Organization::Services::ResolveOperatingUnit::Error,
        Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
        Organization::Services::DefaultOperatingUnit::NotFound => e
        raise InvalidRequest, e.message
      end
      private_class_method :resolve_operating_unit

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

      def self.validate_metadata!(hold_type, reason_code)
        unless Accounts::Models::Hold::HOLD_TYPES.include?(hold_type)
          raise InvalidRequest, "hold_type must be one of: #{Accounts::Models::Hold::HOLD_TYPES.join(", ")}"
        end
        return if Accounts::Models::Hold::REASON_CODES.include?(reason_code)

        raise InvalidRequest, "reason_code must be one of: #{Accounts::Models::Hold::REASON_CODES.join(", ")}"
      end
      private_class_method :validate_metadata!

      def self.validate_expiration!(expires_on, business_date)
        return if expires_on.nil?
        return if expires_on >= business_date.to_date

        raise InvalidRequest, "expires_on must be on or after the business date"
      end
      private_class_method :validate_expiration!
    end
  end
end
