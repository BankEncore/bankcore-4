# frozen_string_literal: true

module Branch
  class OverridesController < ApplicationController
    before_action :require_branch_supervisor_for_approval!

    def new
      @override = default_form_params("branch-override")
    end

    def create
      @override = override_params
      result = Core::OperationalEvents::Commands::RecordControlEvent.call(
        event_type: @override[:event_type],
        channel: "teller",
        idempotency_key: @override[:idempotency_key],
        reference_id: @override[:reference_id],
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::RecordControlEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordControlEvent::MismatchedIdempotency => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    private

    def require_branch_supervisor_for_approval!
      return unless params.dig(:override, :event_type).to_s == "override.approved"

      require_branch_supervisor!
    end

    def default_form_params(prefix)
      {
        "event_type" => params[:event_type] || "override.requested",
        "reference_id" => params[:reference_id],
        "idempotency_key" => default_idempotency_key(prefix)
      }
    end

    def override_params
      params.require(:override).permit(:event_type, :reference_id, :idempotency_key).to_h.symbolize_keys
    end
  end
end
