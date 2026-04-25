# frozen_string_literal: true

module Branch
  class PartiesController < ApplicationController
    def new
      @party = default_party_params
    end

    def create
      @party = party_params
      record = Party::Commands::CreateParty.call(**@party.symbolize_keys)
      redirect_to new_branch_deposit_account_path(party_record_id: record.id),
        notice: "Created party ##{record.id} (#{record.name}). Open a deposit account next."
    rescue Party::Commands::CreateParty::UnsupportedPartyType => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      @error_message = e.record.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end

    private

    def default_party_params
      { "party_type" => "individual" }
    end

    def party_params
      params.require(:party).permit(:party_type, :first_name, :middle_name, :last_name, :name_suffix).to_h
    end
  end
end
