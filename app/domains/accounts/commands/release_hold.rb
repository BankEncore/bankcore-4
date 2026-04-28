# frozen_string_literal: true

module Accounts
  module Commands
    class ReleaseHold
      class Error < StandardError; end
      class InvalidRequest < Error; end
      class HoldNotFound < Error; end
      STAFF_CHANNELS = %w[teller branch].freeze

      # Releases an active hold; creates a posted `hold.released` operational event (no GL).
      def self.call(hold_id:, channel:, idempotency_key:, business_date: nil, actor_id: nil, operating_unit_id: nil)
        ch = channel.to_s
        unless Core::OperationalEvents::Commands::RecordEvent::CHANNELS.include?(ch)
          raise InvalidRequest, "channel must be one of: #{Core::OperationalEvents::Commands::RecordEvent::CHANNELS.join(", ")}"
        end
        resolved_operating_unit = resolve_operating_unit(ch, actor_id, operating_unit_id)
        authorize_staff_release!(ch, actor_id, resolved_operating_unit)

        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        begin
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
        rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
          raise InvalidRequest, e.message
        end

        Core::OperationalEvents::Models::OperationalEvent.transaction do
          existing = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(channel: channel, idempotency_key: idempotency_key)
          if existing
            raise InvalidRequest, "idempotency replay type mismatch" unless existing.event_type == "hold.released"
            hold = Accounts::Models::Hold.find(hold_id)
            raise InvalidRequest, "idempotency replay mismatch" unless existing.source_account_id == hold.deposit_account_id
            raise InvalidRequest, "idempotency replay mismatch" unless existing.operating_unit_id == resolved_operating_unit&.id

            return { outcome: :replay, event: existing, hold: hold.reload }
          end

          hold = Accounts::Models::Hold.lock.find_by(id: hold_id)
          raise HoldNotFound, "hold_id=#{hold_id}" if hold.nil?
          raise InvalidRequest, "hold is not active" unless hold.status == Accounts::Models::Hold::STATUS_ACTIVE

          event = Core::OperationalEvents::Models::OperationalEvent.create!(
            event_type: "hold.released",
            status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
            business_date: on_date,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: hold.amount_minor_units,
            currency: hold.currency,
            source_account_id: hold.deposit_account_id,
            reference_id: hold.id.to_s,
            actor_id: actor_id,
            operating_unit: resolved_operating_unit
          )

          hold.update!(
            status: Accounts::Models::Hold::STATUS_RELEASED,
            released_by_operational_event: event
          )

          { outcome: :created, event: event, hold: hold.reload }
        end
      rescue ActiveRecord::RecordNotUnique
        existing = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
        hold = Accounts::Models::Hold.find(hold_id)
        { outcome: :replay, event: existing, hold: hold.reload }
      end

      def self.resolve_operating_unit(channel, actor_id, operating_unit_id)
        return nil unless STAFF_CHANNELS.include?(channel)

        actor = Workspace::Models::Operator.find_by(id: actor_id) if actor_id.present?
        Organization::Services::ResolveOperatingUnit.call(operator: actor, operating_unit_id: operating_unit_id)
      rescue Organization::Services::ResolveOperatingUnit::Error,
        Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
        Organization::Services::DefaultOperatingUnit::NotFound => e
        raise InvalidRequest, e.message
      end
      private_class_method :resolve_operating_unit

      def self.authorize_staff_release!(channel, actor_id, operating_unit)
        return unless STAFF_CHANNELS.include?(channel)

        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::HOLD_RELEASE,
          scope: operating_unit
        )
      end
      private_class_method :authorize_staff_release!
    end
  end
end
