# frozen_string_literal: true

module Branch
  class AccountStatementsController < ApplicationController
    def index
      @statements = Deposits::Queries::ListDepositStatements.call(
        deposit_account_id: params[:deposit_account_id],
        limit: params[:limit],
        after_id: params[:after_id]
      )
      @account = @statements.account
    end
  end
end
