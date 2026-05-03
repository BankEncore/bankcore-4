# frozen_string_literal: true

module Accounts
  module Commands
    class ExpireDueHolds
      class Error < StandardError; end
      class InvalidRequest < Error; end

      # Expires active holds whose expiration date is due, using `hold.released`
      # as the durable operational event while retaining expired status on the hold.
      def self.call(as_of: nil, channel: "system")
        ch = channel.to_s
        unless Core::OperationalEvents::Commands::RecordEvent::CHANNELS.include?(ch)
          raise InvalidRequest, "channel must be one of: #{Core::OperationalEvents::Commands::RecordEvent::CHANNELS.join(", ")}"
        end

        on_date = normalize_date(as_of || Core::BusinessDate::Services::CurrentBusinessDate.call)
        Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)

        expired = []
        due_scope(on_date).find_each do |hold|
          expired << expire_hold!(hold_id: hold.id, as_of: on_date, channel: ch)
        end
        expired.compact
      rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
        raise InvalidRequest, e.message
      end

      def self.due_scope(as_of)
        Accounts::Models::Hold
          .where(status: Accounts::Models::Hold::STATUS_ACTIVE)
          .where.not(expires_on: nil)
          .where(expires_on: ..normalize_date(as_of))
          .order(:expires_on, :id)
      end

      def self.expire_hold!(hold_id:, as_of:, channel:)
        Accounts::Models::Hold.transaction(requires_new: true) do
          hold = Accounts::Models::Hold.lock.find(hold_id)
          return nil unless hold.status == Accounts::Models::Hold::STATUS_ACTIVE
          return nil if hold.expires_on.blank? || hold.expires_on > as_of

          event = Core::OperationalEvents::Models::OperationalEvent.create!(
            event_type: "hold.released",
            status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
            business_date: as_of,
            channel: channel,
            idempotency_key: "hold-expiration:#{hold.id}:#{as_of.iso8601}",
            amount_minor_units: hold.amount_minor_units,
            currency: hold.currency,
            source_account_id: hold.deposit_account_id,
            reference_id: hold.id.to_s
          )

          hold.update!(
            status: Accounts::Models::Hold::STATUS_EXPIRED,
            released_by_operational_event: event,
            expired_by_operational_event: event
          )

          Accounts::Services::DepositBalanceProjector.refresh_available_balance!(
            deposit_account_id: hold.deposit_account_id,
            operational_event: event,
            as_of_business_date: as_of
          )

          { outcome: :expired, event: event, hold: hold.reload }
        end
      rescue ActiveRecord::RecordNotUnique
        event = Core::OperationalEvents::Models::OperationalEvent.find_by!(
          channel: channel,
          idempotency_key: "hold-expiration:#{hold_id}:#{as_of.iso8601}"
        )
        hold = Accounts::Models::Hold.find(hold_id)
        { outcome: :replay, event: event, hold: hold.reload }
      end

      def self.normalize_date(value)
        value.to_date
      rescue ArgumentError, TypeError, NoMethodError
        raise InvalidRequest, "as_of must be a valid date"
      end
      private_class_method :normalize_date
    end
  end
end
