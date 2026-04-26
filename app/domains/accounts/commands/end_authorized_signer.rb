# frozen_string_literal: true

module Accounts
  module Commands
    class EndAuthorizedSigner
      class Error < StandardError; end
      class InvalidRequest < Error; end

      def self.call(deposit_account_party_id:, channel:, idempotency_key:, actor_id:, ended_on: nil)
        ch = normalize_channel!(channel)
        business_date = current_business_date
        end_date = normalize_date(ended_on.presence || business_date, "ended_on")
        validate_not_backdated!(end_date, business_date, "ended_on")

        Models::DepositAccountParty.transaction(requires_new: true) do
          existing_audit = Models::DepositAccountPartyMaintenanceAudit.lock.find_by(channel: ch, idempotency_key: idempotency_key)
          if existing_audit
            validate_end_replay!(existing_audit, deposit_account_party_id, actor_id, end_date)
            return { outcome: :replay, audit: existing_audit, relationship: existing_audit.deposit_account_party }
          end

          relationship = find_open_authorized_signer!(deposit_account_party_id)
          account = find_open_account!(relationship.deposit_account_id)
          actor = find_supervisor!(actor_id)
          raise InvalidRequest, "ended_on cannot be before effective_on" if end_date < relationship.effective_on

          relationship.update!(
            status: Models::DepositAccountParty::STATUS_INACTIVE,
            ended_on: end_date
          )

          audit = Models::DepositAccountPartyMaintenanceAudit.create!(
            action: Models::DepositAccountPartyMaintenanceAudit::ACTION_AUTHORIZED_SIGNER_ENDED,
            channel: ch,
            idempotency_key: idempotency_key,
            business_date: business_date,
            deposit_account: account,
            party_record: relationship.party_record,
            deposit_account_party: relationship,
            actor: actor,
            role: relationship.role,
            effective_on: relationship.effective_on,
            ended_on: relationship.ended_on
          )

          { outcome: :created, audit: audit, relationship: relationship.reload }
        end
      rescue ActiveRecord::RecordNotUnique
        audit = Models::DepositAccountPartyMaintenanceAudit.find_by(channel: channel.to_s, idempotency_key: idempotency_key)
        raise InvalidRequest, "authorized signer maintenance audit already exists" if audit.nil?

        validate_end_replay!(audit, deposit_account_party_id, actor_id, end_date)
        { outcome: :replay, audit: audit, relationship: audit.deposit_account_party }
      end

      def self.normalize_channel!(channel)
        return channel.to_s if channel.to_s == "branch"

        raise InvalidRequest, "channel must be branch"
      end
      private_class_method :normalize_channel!

      def self.current_business_date
        Core::BusinessDate::Services::CurrentBusinessDate.call.tap do |business_date|
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: business_date)
        end
      rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate, Core::BusinessDate::Errors::NotSet => e
        raise InvalidRequest, e.message
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

      def self.find_open_authorized_signer!(deposit_account_party_id)
        relationship = Models::DepositAccountParty.lock.find_by(id: deposit_account_party_id)
        raise InvalidRequest, "deposit_account_party_id not found" if relationship.nil?
        if relationship.role != Models::DepositAccountParty::ROLE_AUTHORIZED_SIGNER
          raise InvalidRequest, "relationship must be authorized_signer"
        end
        if relationship.status != Models::DepositAccountParty::STATUS_ACTIVE || relationship.ended_on.present?
          raise InvalidRequest, "authorized signer relationship is not active"
        end

        relationship
      end
      private_class_method :find_open_authorized_signer!

      def self.find_open_account!(deposit_account_id)
        account = Models::DepositAccount.find_by(id: deposit_account_id)
        raise InvalidRequest, "deposit_account_id not found" if account.nil?
        return account if account.status == Models::DepositAccount::STATUS_OPEN

        raise InvalidRequest, "deposit account must be open"
      end
      private_class_method :find_open_account!

      def self.find_supervisor!(actor_id)
        actor = Workspace::Models::Operator.find_by(id: actor_id)
        raise InvalidRequest, "actor_id not found" if actor.nil?
        return actor if actor.active? && actor.supervisor?

        raise InvalidRequest, "actor must be an active supervisor"
      end
      private_class_method :find_supervisor!

      def self.validate_end_replay!(audit, deposit_account_party_id, actor_id, ended_on)
        unless audit.action == Models::DepositAccountPartyMaintenanceAudit::ACTION_AUTHORIZED_SIGNER_ENDED &&
            audit.deposit_account_party_id == deposit_account_party_id.to_i &&
            audit.actor_id == actor_id.to_i &&
            audit.ended_on == ended_on
          raise InvalidRequest, "idempotency replay mismatch for authorized signer end"
        end
      end
      private_class_method :validate_end_replay!
    end
  end
end
