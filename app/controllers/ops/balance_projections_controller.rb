# frozen_string_literal: true

module Ops
  class BalanceProjectionsController < ApplicationController
    before_action :require_reconciliation_capability!, only: [ :mark_stale, :rebuild, :create_bulk_repair ]

    def index
      load_health
      load_account_detail if account_lookup.present?
    end

    def mark_stale
      account = find_account_by_id!
      Accounts::Commands::MarkDepositBalanceProjectionStale.call(deposit_account_id: account.id)
      redirect_to ops_balance_projections_path(account: account.account_number),
        notice: "Marked projection stale for account #{account.account_number}."
    rescue ActiveRecord::RecordNotFound
      redirect_to ops_balance_projections_path, alert: "Deposit account was not found."
    end

    def rebuild
      account = find_account_by_id!
      Accounts::Commands::RebuildDepositBalanceProjection.call(deposit_account_id: account.id)
      redirect_to ops_balance_projections_path(account: account.account_number),
        notice: "Rebuilt projection for account #{account.account_number}."
    rescue ActiveRecord::RecordNotFound
      redirect_to ops_balance_projections_path, alert: "Deposit account was not found."
    end

    def bulk_repair
      load_health
    end

    def create_bulk_repair
      outcome = bulk_repair_action
      redirect_to ops_balance_projection_bulk_repair_path, notice: outcome
    rescue ArgumentError => e
      load_health
      @error_message = e.message
      render :bulk_repair, status: :unprocessable_entity
    end

    private

    def load_health
      @health = Accounts::Queries::DepositBalanceProjectionHealth.call
    end

    def account_lookup
      params[:account].to_s.strip
    end

    def load_account_detail
      @account = resolve_account(account_lookup)
      if @account.nil?
        @account_error = "No deposit account matched #{account_lookup.inspect}."
        return
      end

      @projection = @account.deposit_account_balance_projection
      @drift = Accounts::Queries::DepositBalanceProjectionDrift.call(deposit_account_id: @account.id)
      @rebuild_requests = Accounts::Models::DepositBalanceRebuildRequest
        .where(deposit_account_id: @account.id)
        .order(requested_at: :desc, id: :desc)
        .limit(10)
      @daily_snapshots = Reporting::Models::DailyBalanceSnapshot
        .where(
          account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
          account_id: @account.id
        )
        .order(as_of_date: :desc, calculation_version: :desc, id: :desc)
        .limit(10)
    end

    def resolve_account(value)
      if value.match?(/\A\d+\z/)
        Accounts::Models::DepositAccount.find_by(id: value) ||
          Accounts::Models::DepositAccount.find_by(account_number: value)
      else
        Accounts::Models::DepositAccount.find_by(account_number: value)
      end
    end

    def find_account_by_id!
      Accounts::Models::DepositAccount.find(params[:deposit_account_id])
    end

    def require_reconciliation_capability!
      Workspace::Authorization::Authorizer.require_capability!(
        actor_id: current_operator.id,
        capability_code: Workspace::Authorization::CapabilityRegistry::OPS_RECONCILIATION_PERFORM,
        scope: current_operating_unit
      )
    rescue Workspace::Authorization::Forbidden => e
      render plain: e.message, status: :forbidden
    end

    def bulk_repair_action
      case params.dig(:bulk_repair, :action_type).to_s
      when "mark_projection_versions"
        result = Accounts::Commands::MarkDepositBalanceProjectionsStaleForVersion.call
        "Marked #{result.marked_count} projection(s) stale and created #{result.rebuild_requests_created} rebuild request(s)."
      when "mark_snapshot_versions"
        result = Reporting::Commands::MarkDailyBalanceSnapshotsStaleForVersion.call
        "Marked #{result.marked_count} daily snapshot(s) stale."
      when "rebuild_stale_projections"
        count = rebuild_stale_projection_batch
        "Rebuilt #{count} stale projection(s)."
      else
        raise ArgumentError, "Select a valid bulk repair action."
      end
    end

    def rebuild_stale_projection_batch
      limit = Integer(params.dig(:bulk_repair, :limit).presence || 25)
      limit = limit.clamp(1, 200)
      projections = Accounts::Models::DepositAccountBalanceProjection
        .where(stale: true)
        .order(:deposit_account_id)
        .limit(limit)
      projections.count.tap do
        projections.find_each do |projection|
          Accounts::Commands::RebuildDepositBalanceProjection.call(
            deposit_account_id: projection.deposit_account_id,
            reason: Accounts::Models::DepositBalanceRebuildRequest::REASON_MANUAL_REBUILD
          )
        end
      end
    end
  end
end
