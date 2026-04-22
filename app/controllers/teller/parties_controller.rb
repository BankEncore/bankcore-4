# frozen_string_literal: true

module Teller
  class PartiesController < ApplicationController
    def create
      record = Party::Commands::CreateParty.call(**create_params)
      render json: { id: record.id, name: record.name, party_type: record.party_type }, status: :created
    rescue Party::Commands::CreateParty::UnsupportedPartyType => e
      render json: { error: e.class.name, message: e.message }, status: :unprocessable_entity
    end

    private

    def create_params
      params.permit(:party_type, :first_name, :middle_name, :last_name, :name_suffix).to_h.symbolize_keys
    end
  end
end
