# frozen_string_literal: true

module Accounts
  module Commands
    class CloseAccount
      class Error < StandardError; end
      class InvalidRequest < Error; end

      def self.call(deposit_account_id:, reason_code:, idempotency_key:, actor_id:, channel: "branch",
        reason_description: nil, effective_on: nil)
        ch = normalize_channel!(channel)
        business_date = current_business_date
        on_date = normalize_date(effective_on.presence || business_date, "effective_on")
        validate_not_backdated!(on_date, business_date, "effective_on")

        Models::DepositAccount.transaction(requires_new: true) do
          existing = Models::AccountLifecycleEvent.lock.find_by(channel: ch, idempotency_key: idempotency_key)
          if existing
            validate_replay!(existing, deposit_account_id, reason_code, reason_description, actor_id, on_date)
            return { outcome: :replay, lifecycle_event: existing, event: existing.operational_event }
          end

          account = Models::DepositAccount.lock.find_by(id: deposit_account_id)
          raise InvalidRequest, "deposit_account_id not found" if account.nil?
          raise InvalidRequest, "deposit account must be open" unless account.status == Models::DepositAccount::STATUS_OPEN

          actor = authorize_actor!(actor_id)
          validate_zero_balance!(account)
          validate_no_active_holds!(account)
          validate_no_pending_events!(account)
          Services::AccountRestrictionPolicy.assert_close_allowed!(deposit_account_id: account.id)

          lifecycle_event = Models::AccountLifecycleEvent.create!(
            deposit_account: account,
            action: Models::AccountLifecycleEvent::ACTION_CLOSED,
            channel: ch,
            idempotency_key: idempotency_key,
            business_date: business_date,
            actor: actor,
            reason_code: normalize_required_string(reason_code, "reason_code"),
            reason_description: reason_description.presence,
            effective_on: on_date
          )
          event = record_event!(lifecycle_event)
          lifecycle_event.update!(operational_event: event)
          account.update!(status: Models::DepositAccount::STATUS_CLOSED)
          { outcome: :created, lifecycle_event: lifecycle_event.reload, event: event }
        end
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
      rescue AccountRestricted,
        Core::OperationalEvents::Commands::RecordControlEvent::Error,
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

      def self.validate_zero_balance!(account)
        ledger = Services::AvailableBalanceMinorUnits.ledger_balance_minor_units(deposit_account_id: account.id)
        available = Services::AvailableBalanceMinorUnits.call(deposit_account_id: account.id)
        return if ledger.zero? && available.zero?

        raise InvalidRequest, "account balance must be zero before close"
      end
      private_class_method :validate_zero_balance!

      def self.validate_no_active_holds!(account)
        return unless Models::Hold.where(deposit_account: account, status: Models::Hold::STATUS_ACTIVE).exists?

        raise InvalidRequest, "active holds must be resolved before close"
      end
      private_class_method :validate_no_active_holds!

      def self.validate_no_pending_events!(account)
        pending = Core::OperationalEvents::Models::OperationalEvent.where(
          status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING
        ).where("source_account_id = :id OR destination_account_id = :id", id: account.id)
        return unless pending.exists?

        raise InvalidRequest, "pending operational events must be resolved before close"
      end
      private_class_method :validate_no_pending_events!

      def self.record_event!(lifecycle_event)
        Core::OperationalEvents::Commands::RecordControlEvent.call(
          event_type: "account.closed",
          channel: lifecycle_event.channel,
          idempotency_key: "account-closed:#{lifecycle_event.id}",
          reference_id: lifecycle_event.id.to_s,
          actor_id: lifecycle_event.actor_id,
          business_date: lifecycle_event.business_date,
          source_account_id: lifecycle_event.deposit_account_id
        )[:event]
      end
      private_class_method :record_event!

      def self.validate_replay!(existing, deposit_account_id, reason_code, reason_description, actor_id, effective_on)
        unless existing.action == Models::AccountLifecycleEvent::ACTION_CLOSED &&
            existing.deposit_account_id == deposit_account_id.to_i &&
            existing.reason_code == reason_code.to_s &&
            existing.reason_description.to_s == reason_description.to_s &&
            existing.actor_id == actor_id.to_i &&
            existing.effective_on == effective_on
          raise InvalidRequest, "idempotency replay mismatch for account close"
        end
      end
      private_class_method :validate_replay!

      def self.normalize_required_string(value, field_name)
        normalized = value.to_s.strip
        raise InvalidRequest, "#{field_name} is required" if normalized.blank?

        normalized
      end
      private_class_method :normalize_required_string
    end
  end
end
