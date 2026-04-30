# frozen_string_literal: true

module Accounts
  module Commands
    class UnrestrictAccount
      class Error < StandardError; end
      class InvalidRequest < Error; end

      def self.call(account_restriction_id:, idempotency_key:, actor_id:, channel: "branch", released_on: nil)
        ch = normalize_channel!(channel)
        business_date = current_business_date
        release_date = normalize_date(released_on.presence || business_date, "released_on")
        validate_not_backdated!(release_date, business_date, "released_on")

        Models::AccountRestriction.transaction(requires_new: true) do
          existing = Models::AccountRestriction.lock.find_by(release_idempotency_key: idempotency_key)
          if existing
            validate_replay!(existing, account_restriction_id, actor_id, release_date)
            return { outcome: :replay, restriction: existing, event: existing.unrestricted_operational_event }
          end

          restriction = Models::AccountRestriction.lock.find_by(id: account_restriction_id)
          raise InvalidRequest, "account_restriction_id not found" if restriction.nil?
          raise InvalidRequest, "account restriction is not active" unless restriction.active?

          actor = authorize_actor!(actor_id)
          raise InvalidRequest, "released_on cannot be before effective_on" if release_date < restriction.effective_on

          restriction.update!(
            status: Models::AccountRestriction::STATUS_RELEASED,
            released_by_actor: actor,
            released_on: release_date,
            release_idempotency_key: idempotency_key
          )
          event = record_event!(restriction, ch, business_date)
          restriction.update!(unrestricted_operational_event: event)
          { outcome: :created, restriction: restriction.reload, event: event }
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      rescue Core::OperationalEvents::Commands::RecordControlEvent::Error,
        Workspace::Authorization::Forbidden,
        Core::BusinessDate::Errors::InvalidPostingBusinessDate,
        Core::BusinessDate::Errors::NotSet => e
        raise InvalidRequest, e.message
      end

      def self.normalize_channel!(channel)
        return "branch" if channel.to_s == "branch"

        raise InvalidRequest, "channel must be branch"
      end
      private_class_method :normalize_channel!

      def self.current_business_date
        Core::BusinessDate::Services::CurrentBusinessDate.call.tap do |business_date|
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: business_date)
        end
      end
      private_class_method :current_business_date

      def self.normalize_date(value, field)
        value.to_date
      rescue ArgumentError, TypeError, NoMethodError
        raise InvalidRequest, "#{field} must be a valid date"
      end
      private_class_method :normalize_date

      def self.validate_not_backdated!(date, business_date, field)
        return if date >= business_date

        raise InvalidRequest, "#{field} cannot be before the current business date"
      end
      private_class_method :validate_not_backdated!

      def self.authorize_actor!(actor_id)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN
        )
      end
      private_class_method :authorize_actor!

      def self.record_event!(restriction, channel, business_date)
        Core::OperationalEvents::Commands::RecordControlEvent.call(
          event_type: "account.unrestricted",
          channel: channel,
          idempotency_key: "account-unrestricted:#{restriction.id}",
          reference_id: restriction.id.to_s,
          actor_id: restriction.released_by_actor_id,
          business_date: business_date,
          source_account_id: restriction.deposit_account_id
        )[:event]
      end
      private_class_method :record_event!

      def self.validate_replay!(existing, account_restriction_id, actor_id, released_on)
        unless existing.id == account_restriction_id.to_i &&
            existing.released_by_actor_id == actor_id.to_i &&
            existing.released_on == released_on
          raise InvalidRequest, "idempotency replay mismatch for account unrestriction"
        end
      end
      private_class_method :validate_replay!
    end
  end
end
