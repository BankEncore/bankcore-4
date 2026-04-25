# frozen_string_literal: true

module Branch
  class CustomersController < ApplicationController
    def index
      @query = params[:query].to_s.strip
      @search = Party::Queries::PartySearch.call(query: @query, limit: params[:limit]) if @query.present?
    end

    def show
      @party = Party::Queries::FindParty.by_id(params[:id])
      @account_relationships = Accounts::Queries::DepositAccountsForParty.call(party_record_id: @party.id).rows
    end
  end
end
