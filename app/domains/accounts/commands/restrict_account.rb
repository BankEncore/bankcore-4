# frozen_string_literal: true

module Accounts
  module Commands
    class RestrictAccount
      class Error < StandardError; end
      class InvalidRequest < Error; end

      def self.call(deposit_account_id:, restriction_type:, reason_code:, idempotency_key:, actor_id:,
        channel: "branch", reason_description: nil, effective_on: nil)
        ch = normalize_channel!(channel)
        business_date = current_business_date
        on_date = normalize_date(effective_on.presence || business_date, "effective_on")
        validate_not_backdated!(on_date, business_date, "effective_on")
        validate_restriction_type!(restriction_type)

        Models::AccountRestriction.transaction(requires_new: true) do
          existing = Models::AccountRestriction.lock.find_by(channel: ch, idempotency_key: idempotency_key)
          if existing
            validate_replay!(existing, deposit_account_id, restriction_type, reason_code, reason_description, actor_id, on_date)
            return { outcome: :replay, restriction: existing, event: existing.restricted_operational_event }
          end

          account = find_open_account!(deposit_account_id)
          actor = authorize_actor!(actor_id)
          restriction = Models::AccountRestriction.create!(
            deposit_account: account,
            restriction_type: restriction_type.to_s,
            status: Models::AccountRestriction::STATUS_ACTIVE,
            channel: ch,
            idempotency_key: idempotency_key,
            business_date: business_date,
            actor: actor,
            reason_code: normalize_required_string(reason_code, "reason_code"),
            reason_description: reason_description.presence,
            effective_on: on_date
          )
          event = record_event!(restriction)
          restriction.update!(restricted_operational_event: event)
          { outcome: :created, restriction: restriction.reload, event: event }
        end
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
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

      def self.validate_restriction_type!(restriction_type)
        return if Models::AccountRestriction::RESTRICTION_TYPES.include?(restriction_type.to_s)

        raise InvalidRequest, "restriction_type must be one of: #{Models::AccountRestriction::RESTRICTION_TYPES.join(', ')}"
      end
      private_class_method :validate_restriction_type!

      def self.find_open_account!(deposit_account_id)
        account = Models::DepositAccount.find_by(id: deposit_account_id)
        raise InvalidRequest, "deposit_account_id not found" if account.nil?
        return account if account.status == Models::DepositAccount::STATUS_OPEN

        raise InvalidRequest, "deposit account must be open"
      end
      private_class_method :find_open_account!

      def self.authorize_actor!(actor_id)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN
        )
      end
      private_class_method :authorize_actor!

      def self.record_event!(restriction)
        Core::OperationalEvents::Commands::RecordControlEvent.call(
          event_type: "account.restricted",
          channel: restriction.channel,
          idempotency_key: "account-restricted:#{restriction.id}",
          reference_id: restriction.id.to_s,
          actor_id: restriction.actor_id,
          business_date: restriction.business_date,
          source_account_id: restriction.deposit_account_id
        )[:event]
      end
      private_class_method :record_event!

      def self.validate_replay!(existing, deposit_account_id, restriction_type, reason_code, reason_description, actor_id, effective_on)
        unless existing.deposit_account_id == deposit_account_id.to_i &&
            existing.restriction_type == restriction_type.to_s &&
            existing.reason_code == reason_code.to_s &&
            existing.reason_description.to_s == reason_description.to_s &&
            existing.actor_id == actor_id.to_i &&
            existing.effective_on == effective_on
          raise InvalidRequest, "idempotency replay mismatch for account restriction"
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
