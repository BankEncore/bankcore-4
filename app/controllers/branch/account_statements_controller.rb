# frozen_string_literal: true

module Branch
  class AccountStatementsController < ApplicationController
    def index
      load_account_context!(deposit_account_id: params[:deposit_account_id])
      @statements = Deposits::Queries::ListDepositStatements.call(
        deposit_account_id: @account.id,
        limit: params[:limit],
        after_id: params[:after_id]
      )
    end
  end
end
