# frozen_string_literal: true

module Accounts
  module Commands
    class AddAuthorizedSigner
      class Error < StandardError; end
      class InvalidRequest < Error; end

      def self.call(deposit_account_id:, party_record_id:, channel:, idempotency_key:, actor_id:, effective_on: nil)
        ch = normalize_channel!(channel)
        business_date = current_business_date
        on_date = normalize_date(effective_on.presence || business_date, "effective_on")
        validate_not_backdated!(on_date, business_date, "effective_on")

        Models::DepositAccountParty.transaction(requires_new: true) do
          existing_audit = Models::DepositAccountPartyMaintenanceAudit.lock.find_by(channel: ch, idempotency_key: idempotency_key)
          if existing_audit
            validate_add_replay!(existing_audit, deposit_account_id, party_record_id, actor_id, on_date)
            return { outcome: :replay, audit: existing_audit, relationship: existing_audit.deposit_account_party }
          end

          account = find_open_account!(deposit_account_id)
          party = find_party!(party_record_id)
          actor = find_supervisor!(actor_id)
          ensure_no_open_authorized_signer!(account.id, party.id)

          relationship = Models::DepositAccountParty.create!(
            deposit_account: account,
            party_record: party,
            role: Models::DepositAccountParty::ROLE_AUTHORIZED_SIGNER,
            status: Models::DepositAccountParty::STATUS_ACTIVE,
            effective_on: on_date,
            ended_on: nil
          )

          audit = Models::DepositAccountPartyMaintenanceAudit.create!(
            action: Models::DepositAccountPartyMaintenanceAudit::ACTION_AUTHORIZED_SIGNER_ADDED,
            channel: ch,
            idempotency_key: idempotency_key,
            business_date: business_date,
            deposit_account: account,
            party_record: party,
            deposit_account_party: relationship,
            actor: actor,
            role: relationship.role,
            effective_on: relationship.effective_on,
            ended_on: nil
          )

          { outcome: :created, audit: audit, relationship: relationship }
        end
      rescue ActiveRecord::RecordNotUnique
        audit = Models::DepositAccountPartyMaintenanceAudit.find_by(channel: channel.to_s, idempotency_key: idempotency_key)
        raise InvalidRequest, "party already has active authorized signer authority on this account" if audit.nil?

        validate_add_replay!(audit, deposit_account_id, party_record_id, actor_id, on_date)
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

      def self.find_open_account!(deposit_account_id)
        account = Models::DepositAccount.find_by(id: deposit_account_id)
        raise InvalidRequest, "deposit_account_id not found" if account.nil?
        return account if account.status == Models::DepositAccount::STATUS_OPEN

        raise InvalidRequest, "deposit account must be open"
      end
      private_class_method :find_open_account!

      def self.find_party!(party_record_id)
        Party::Models::PartyRecord.find(party_record_id)
      rescue ActiveRecord::RecordNotFound
        raise InvalidRequest, "party_record_id not found"
      end
      private_class_method :find_party!

      def self.find_supervisor!(actor_id)
        actor = Workspace::Models::Operator.find_by(id: actor_id)
        raise InvalidRequest, "actor_id not found" if actor.nil?
        return actor if actor.active? && actor.supervisor?

        raise InvalidRequest, "actor must be an active supervisor"
      end
      private_class_method :find_supervisor!

      def self.ensure_no_open_authorized_signer!(deposit_account_id, party_record_id)
        existing = Models::DepositAccountParty.exists?(
          deposit_account_id: deposit_account_id,
          party_record_id: party_record_id,
          role: Models::DepositAccountParty::ROLE_AUTHORIZED_SIGNER,
          status: Models::DepositAccountParty::STATUS_ACTIVE,
          ended_on: nil
        )
        raise InvalidRequest, "party already has active authorized signer authority on this account" if existing
      end
      private_class_method :ensure_no_open_authorized_signer!

      def self.validate_add_replay!(audit, deposit_account_id, party_record_id, actor_id, effective_on)
        unless audit.action == Models::DepositAccountPartyMaintenanceAudit::ACTION_AUTHORIZED_SIGNER_ADDED &&
            audit.deposit_account_id == deposit_account_id.to_i &&
            audit.party_record_id == party_record_id.to_i &&
            audit.actor_id == actor_id.to_i &&
            audit.effective_on == effective_on
          raise InvalidRequest, "idempotency replay mismatch for authorized signer add"
        end
      end
      private_class_method :validate_add_replay!
    end
  end
end
