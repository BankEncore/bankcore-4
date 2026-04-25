# frozen_string_literal: true

module Deposits
  module Commands
    class GenerateDepositStatements
      OUTCOME_GENERATED = :generated
      OUTCOME_ALREADY_GENERATED = :already_generated
      OUTCOME_NOT_DUE = :not_due

      Result = Data.define(:business_date, :outcomes) do
        def counts
          outcomes.each_with_object(Hash.new(0)) { |row, memo| memo[row.fetch(:outcome)] += 1 }
        end
      end

      def self.call(business_date: nil, deposit_product_id: nil, account_ids: nil, preview: false)
        on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
        profiles = Products::Queries::ActiveStatementProfiles.monthly(
          business_date: on_date,
          deposit_product_id: deposit_product_id
        )

        outcomes = []
        profiles.find_each do |profile|
          eligible_accounts(profile, account_ids).find_each do |account|
            account_outcomes = if preview
              preview_for_account(profile: profile, account: account, business_date: on_date)
            else
              generate_for_account(profile: profile, account: account, business_date: on_date)
            end
            outcomes.concat(account_outcomes)
          end
        end

        Result.new(business_date: on_date, outcomes: outcomes)
      end

      def self.eligible_accounts(profile, account_ids)
        scope = Accounts::Models::DepositAccount.where(
          deposit_product_id: profile.deposit_product_id,
          status: Accounts::Models::DepositAccount::STATUS_OPEN
        ).order(:id)
        scope = scope.where(id: account_ids) if account_ids.present?
        scope
      end
      private_class_method :eligible_accounts

      def self.generate_for_account(profile:, account:, business_date:)
        last_statement = Models::DepositStatement
          .where(deposit_account_id: account.id, deposit_product_statement_profile_id: profile.id)
          .order(period_end_on: :desc, id: :desc)
          .first
        last_complete = Services::StatementCycleService.last_completed_period(
          generated_on: business_date,
          cycle_day: profile.cycle_day
        )
        if last_statement && last_complete && last_statement.period_end_on >= last_complete.period_end_on
          return [ outcome_row(profile: profile, account: account, statement: last_statement, outcome: OUTCOME_ALREADY_GENERATED) ]
        end

        periods = Services::StatementCycleService.due_periods(
          profile: profile,
          account: account,
          generated_on: business_date,
          last_statement: last_statement
        )
        return [ outcome_row(profile: profile, account: account, outcome: OUTCOME_NOT_DUE) ] if periods.empty?

        periods.map do |period|
          generate_period(profile: profile, account: account, period: period, business_date: business_date)
        end
      end
      private_class_method :generate_for_account

      def self.preview_for_account(profile:, account:, business_date:)
        last_statement = Models::DepositStatement
          .where(deposit_account_id: account.id, deposit_product_statement_profile_id: profile.id)
          .order(period_end_on: :desc, id: :desc)
          .first
        last_complete = Services::StatementCycleService.last_completed_period(
          generated_on: business_date,
          cycle_day: profile.cycle_day
        )
        if last_statement && last_complete && last_statement.period_end_on >= last_complete.period_end_on
          return [ outcome_row(profile: profile, account: account, statement: last_statement, outcome: OUTCOME_ALREADY_GENERATED) ]
        end

        periods = Services::StatementCycleService.due_periods(
          profile: profile,
          account: account,
          generated_on: business_date,
          last_statement: last_statement
        )
        return [ outcome_row(profile: profile, account: account, outcome: OUTCOME_NOT_DUE) ] if periods.empty?

        periods.map do |period|
          outcome_row(
            profile: profile,
            account: account,
            outcome: OUTCOME_GENERATED,
            period_start_on: period.period_start_on,
            period_end_on: period.period_end_on
          )
        end
      end
      private_class_method :preview_for_account

      def self.generate_period(profile:, account:, period:, business_date:)
        existing = Models::DepositStatement.find_by(
          deposit_account_id: account.id,
          period_start_on: period.period_start_on,
          period_end_on: period.period_end_on
        )
        return outcome_row(profile: profile, account: account, statement: existing, outcome: OUTCOME_ALREADY_GENERATED) if existing

        activity = Queries::StatementActivity.call(
          deposit_account_id: account.id,
          period_start_on: period.period_start_on,
          period_end_on: period.period_end_on
        )
        statement = Models::DepositStatement.create!(
          deposit_account: account,
          deposit_product_statement_profile: profile,
          period_start_on: period.period_start_on,
          period_end_on: period.period_end_on,
          currency: account.currency,
          opening_ledger_balance_minor_units: activity.opening_ledger_balance_minor_units,
          closing_ledger_balance_minor_units: activity.closing_ledger_balance_minor_units,
          total_debits_minor_units: activity.total_debits_minor_units,
          total_credits_minor_units: activity.total_credits_minor_units,
          line_items: activity.line_items,
          status: Models::DepositStatement::STATUS_GENERATED,
          generated_on: business_date,
          generated_at: Time.current,
          idempotency_key: idempotency_key(account: account, period: period)
        )

        outcome_row(profile: profile, account: account, statement: statement, outcome: OUTCOME_GENERATED)
      rescue ActiveRecord::RecordNotUnique
        statement = Models::DepositStatement.find_by!(
          deposit_account_id: account.id,
          period_start_on: period.period_start_on,
          period_end_on: period.period_end_on
        )
        outcome_row(profile: profile, account: account, statement: statement, outcome: OUTCOME_ALREADY_GENERATED)
      end
      private_class_method :generate_period

      def self.idempotency_key(account:, period:)
        "deposit-statement:#{account.id}:#{period.period_start_on.iso8601}:#{period.period_end_on.iso8601}"
      end

      def self.outcome_row(profile:, account:, outcome:, statement: nil, period_start_on: nil, period_end_on: nil)
        {
          outcome: outcome,
          deposit_account_id: account.id,
          deposit_product_statement_profile_id: profile.id,
          deposit_statement_id: statement&.id,
          period_start_on: period_start_on || statement&.period_start_on,
          period_end_on: period_end_on || statement&.period_end_on
        }.compact
      end
      private_class_method :outcome_row
    end
  end
end
