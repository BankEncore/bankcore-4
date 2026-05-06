# frozen_string_literal: true

module Branch
  class CustomersController < ApplicationController
    def index
      @branch_surface = "csr"
      @query = params[:query].to_s.strip
      @search = Party::Queries::PartySearch.call(query: @query, limit: params[:limit]) if @query.present?
    end

    def show
      @branch_surface = "csr"
      @party = Party::Queries::FindParty.by_id(params[:id])
      @account_relationships = Accounts::Queries::DepositAccountPartyTimeline.call(party_record_id: @party.id)
      @contact_summary = Party::Queries::PartyContactSummary.call(party_record_id: @party.id)
    end
  end
end
