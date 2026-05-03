# frozen_string_literal: true

module Branch
  class ServicingDepositAccountsController < ApplicationController
    RECENT_ACTIVITY_DAYS = 30
    RECENT_ACTIVITY_LIMIT = 10
    OPERATIONAL_EVENTS_FETCH_LIMIT = 50
    OPERATIONAL_EVENTS_DISPLAY_LIMIT = 10

    def show
      load_account_context!(deposit_account_id: params[:id])
      @account_relationships = Accounts::Queries::DepositAccountPartyTimeline.call(deposit_account_id: @account.id)
      @holds = Accounts::Queries::ListHoldsForAccount.call(deposit_account_id: @account.id, limit: 10)
      @statements = Deposits::Queries::ListDepositStatements.call(deposit_account_id: @account.id, limit: 5)
      @activity = Deposits::Queries::StatementActivity.call(
        deposit_account_id: @account.id,
        period_start_on: activity_start_on,
        period_end_on: activity_end_on
      )
      @recent_activity_line_items = recent_activity_line_items
      @events = account_operational_events(excluding_event_ids: recent_activity_event_ids)
      @can_place_holds = can_place_servicing_hold?
      @can_release_holds = can_release_servicing_hold?
      @can_waive_fees = can_waive_fee?
      @can_reverse_events = can_reverse_event?
    rescue Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery => e
      redirect_to branch_path, alert: e.message
    end

    private

    def activity_end_on
      @activity_end_on ||= @profile.current_business_date || Date.current
    end

    def activity_start_on
      @activity_start_on ||= activity_end_on - RECENT_ACTIVITY_DAYS
    end

    def recent_activity_line_items
      @activity.line_items.select { |line| line.fetch(:affects_ledger) }.take(RECENT_ACTIVITY_LIMIT)
    end

    def recent_activity_event_ids
      @recent_activity_line_items.filter_map { |line| line[:operational_event_id] }
    end

    def account_operational_events(excluding_event_ids:)
      source_events = list_operational_events(source_account_id: @account.id)
      destination_events = list_operational_events(destination_account_id: @account.id)
      rows = (source_events[:rows] + destination_events[:rows])
        .uniq(&:id)
        .sort_by(&:id)
        .reject { |event| excluding_event_ids.include?(event.id) }
        .take(OPERATIONAL_EVENTS_DISPLAY_LIMIT)

      source_events.merge(rows: rows)
    end

    def list_operational_events(source_account_id: nil, destination_account_id: nil)
      Core::OperationalEvents::Queries::ListOperationalEvents.call(
        business_date_from: activity_start_on,
        business_date_to: activity_end_on,
        source_account_id: source_account_id,
        destination_account_id: destination_account_id,
        limit: OPERATIONAL_EVENTS_FETCH_LIMIT
      )
    end
  end
end
