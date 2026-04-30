# frozen_string_literal: true

module Branch
  class PartyContactsController < ApplicationController
    before_action :load_party
    before_action :require_party_contact_update_capability!

    def new
      @contact = default_contact_params
    end

    def create
      @contact = contact_params.with_indifferent_access
      result = Party::Commands::UpdateContactPoint.call(
        party_record_id: @party.id,
        contact_type: @contact[:contact_type],
        purpose: @contact[:purpose],
        value: @contact[:value],
        attributes: address_attributes,
        effective_on: @contact[:effective_on],
        idempotency_key: @contact[:idempotency_key],
        actor_id: current_operator.id,
        channel: branch_channel
      )
      redirect_to branch_customer_path(@party),
        notice: result[:outcome] == :replay ? "Party contact update already recorded." : "Party contact updated."
    rescue Party::Commands::UpdateContactPoint::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    private

    def load_party
      @party = Party::Models::PartyRecord.find(params[:party_record_id])
    end

    def require_party_contact_update_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::PARTY_CONTACT_UPDATE)
    end

    def default_contact_params
      {
        "contact_type" => "email",
        "purpose" => Party::Models::PartyEmail::PURPOSE_PRIMARY,
        "effective_on" => Core::BusinessDate::Services::CurrentBusinessDate.call,
        "idempotency_key" => default_idempotency_key("branch-party-contact")
      }
    rescue Core::BusinessDate::Errors::NotSet
      {
        "contact_type" => "email",
        "purpose" => Party::Models::PartyEmail::PURPOSE_PRIMARY,
        "effective_on" => Date.current,
        "idempotency_key" => default_idempotency_key("branch-party-contact")
      }
    end

    def contact_params
      params.require(:contact).permit(
        :contact_type,
        :purpose,
        :value,
        :line1,
        :line2,
        :city,
        :region,
        :postal_code,
        :country,
        :effective_on,
        :idempotency_key
      ).to_h
    end

    def address_attributes
      @contact.slice(:line1, :line2, :city, :region, :postal_code, :country)
    end
  end
end
