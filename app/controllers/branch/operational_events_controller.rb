# frozen_string_literal: true

module Branch
  class OperationalEventsController < ApplicationController
    def index
      @query_params = permitted_query_params
      apply_branch_operating_unit_default!

      if @query_params[:operating_unit_id].present?
        begin
          Organization::Services::ResolveOperatingUnit.assert_operator_scoped_to_operating_unit!(
            operator: current_operator,
            operating_unit_id: @query_params[:operating_unit_id]
          )
        rescue Organization::Services::ResolveOperatingUnit::NotAuthorized => e
          @error_message = e.message
          @event_search = nil
          render :index, status: :unprocessable_entity
          return
        end
      end

      @event_search = Core::OperationalEvents::Queries::ListOperationalEvents.call(**@query_params)
      @scoped_operating_unit = Organization::Models::OperatingUnit.find_by(id: @query_params[:operating_unit_id]) if @query_params[:operating_unit_id].present?
    rescue Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery => e
      @error_message = e.message
      @event_search = nil
      render :index, status: :unprocessable_entity
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      @event_search = nil
      render :index, status: :unprocessable_entity
    end

    def show
      @event = load_event
    end

    def receipt
      @event = load_event
    end

    private

    def apply_branch_operating_unit_default!
      @branch_events_show_all_units = ActiveModel::Type::Boolean.new.cast(params[:all_units])
      if @branch_events_show_all_units
        @query_params.delete(:operating_unit_id)
        @branch_events_defaulted_operating_unit = nil
        return
      end

      return if @query_params[:operating_unit_id].present?

      if current_operating_unit.present?
        @query_params[:operating_unit_id] = current_operating_unit.id
        @branch_events_defaulted_operating_unit = current_operating_unit
      end
    end

    def load_event
      Core::OperationalEvents::Models::OperationalEvent.includes(
        :source_account,
        :destination_account,
        :teller_session,
        :actor,
        :reversal_of_event,
        :operating_unit,
        { posting_batches: :journal_entries }
      ).find(params[:id])
    end

    def permitted_query_params
      p = params.permit(
        :business_date, :business_date_from, :business_date_to,
        :source_account_id, :destination_account_id, :status, :event_type, :channel, :actor_id,
        :operating_unit_id, :after_id, :limit,
        event_type_in: []
      ).to_h.symbolize_keys
      p[:source_account_id] = p[:source_account_id].to_i if p[:source_account_id].present?
      p[:destination_account_id] = p[:destination_account_id].to_i if p[:destination_account_id].present?
      p[:actor_id] = p[:actor_id].to_i if p[:actor_id].present?
      if p[:event_type_in].present?
        p[:event_type_in] = Array.wrap(p[:event_type_in]).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:blank?)
      else
        p.delete(:event_type_in)
      end
      if p[:operating_unit_id].present?
        ou = p[:operating_unit_id].to_i
        if ou.positive?
          p[:operating_unit_id] = ou
        else
          p.delete(:operating_unit_id)
        end
      end
      p
    end
  end
end
