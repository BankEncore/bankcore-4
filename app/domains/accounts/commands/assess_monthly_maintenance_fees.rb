# frozen_string_literal: true

module Accounts
  module Commands
    class AssessMonthlyMaintenanceFees
      class Error < StandardError; end
      class InvalidRequest < Error; end

      OUTCOME_POSTED = :posted
      OUTCOME_ALREADY_POSTED = :already_posted
      OUTCOME_SKIPPED_INSUFFICIENT_AVAILABLE_BALANCE = :skipped_insufficient_available_balance

      Result = Data.define(:business_date, :outcomes) do
        def counts
          outcomes.each_with_object(Hash.new(0)) { |row, memo| memo[row.fetch(:outcome)] += 1 }
        end
      end

      def self.call(business_date: nil, deposit_product_id: nil, account_ids: nil, channel: "system", preview: false)
        raise InvalidRequest, "monthly maintenance fee engine may only use channel system" unless channel.to_s == "system"

        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        rules = Products::Queries::ActiveFeeRules.monthly_maintenance(
          business_date: on_date,
          deposit_product_id: deposit_product_id
        )

        outcomes = []
        rules.find_each do |rule|
          eligible_accounts(rule, account_ids).find_each do |account|
            outcomes << if preview
              preview_account(rule, account, on_date, channel)
            else
              assess_account(rule, account, on_date, channel)
            end
          end
        end

        Result.new(business_date: on_date, outcomes: outcomes)
      end

      def self.eligible_accounts(rule, account_ids)
        scope = Accounts::Models::DepositAccount.where(
          deposit_product_id: rule.deposit_product_id,
          status: Accounts::Models::DepositAccount::STATUS_OPEN
        ).order(:id)
        scope = scope.where(id: account_ids) if account_ids.present?
        scope
      end
      private_class_method :eligible_accounts

      def self.assess_account(rule, account, business_date, channel)
        idem = idempotency_key(rule: rule, account: account, business_date: business_date)
        ref = reference_id(rule: rule, business_date: business_date)

        begin
          record = Core::OperationalEvents::Commands::RecordEvent.call(
            event_type: "fee.assessed",
            channel: channel,
            idempotency_key: idem,
            amount_minor_units: rule.amount_minor_units,
            currency: rule.currency,
            source_account_id: account.id,
            business_date: business_date,
            reference_id: ref
          )
          post_result = Core::Posting::Commands::PostEvent.call(operational_event_id: record[:event].id)
          outcome = post_result[:outcome] == :already_posted ? OUTCOME_ALREADY_POSTED : OUTCOME_POSTED
          outcome_row(rule: rule, account: account, event: record[:event], outcome: outcome)
        rescue Core::OperationalEvents::Commands::RecordEvent::PostedReplay
          existing = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idem)
          post_result = Core::Posting::Commands::PostEvent.call(operational_event_id: existing.id)
          outcome = post_result[:outcome] == :already_posted ? OUTCOME_ALREADY_POSTED : OUTCOME_POSTED
          outcome_row(rule: rule, account: account, event: existing, outcome: outcome)
        rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest => e
          raise unless e.message.match?(/insufficient available balance/i)

          outcome_row(
            rule: rule,
            account: account,
            event: nil,
            outcome: OUTCOME_SKIPPED_INSUFFICIENT_AVAILABLE_BALANCE,
            message: e.message
          )
        end
      end
      private_class_method :assess_account

      def self.preview_account(rule, account, business_date, channel)
        idem = idempotency_key(rule: rule, account: account, business_date: business_date)
        existing = Core::OperationalEvents::Models::OperationalEvent.find_by(channel: channel, idempotency_key: idem)
        if existing
          outcome = existing.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED ? OUTCOME_ALREADY_POSTED : OUTCOME_POSTED
          return outcome_row(rule: rule, account: account, event: existing, outcome: outcome)
        end

        available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: account.id)
        if available < rule.amount_minor_units.to_i
          return outcome_row(
            rule: rule,
            account: account,
            event: nil,
            outcome: OUTCOME_SKIPPED_INSUFFICIENT_AVAILABLE_BALANCE,
            message: "insufficient available balance"
          )
        end

        outcome_row(rule: rule, account: account, event: nil, outcome: OUTCOME_POSTED)
      end
      private_class_method :preview_account

      def self.idempotency_key(rule:, account:, business_date:)
        "monthly-maintenance:#{business_date.iso8601}:#{rule.id}:#{account.id}"
      end

      def self.reference_id(rule:, business_date:)
        "monthly_maintenance:#{rule.id}:#{business_date.iso8601}"
      end

      def self.outcome_row(rule:, account:, event:, outcome:, message: nil)
        {
          outcome: outcome,
          deposit_account_id: account.id,
          deposit_product_fee_rule_id: rule.id,
          operational_event_id: event&.id,
          message: message
        }.compact
      end
      private_class_method :outcome_row
    end
  end
end
