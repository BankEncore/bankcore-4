# frozen_string_literal: true

module Deposits
  module Queries
    class ListDepositStatements
      DEFAULT_LIMIT = 24
      MAX_LIMIT = 100

      Result = Data.define(:account, :rows, :next_after_id, :has_more)

      def self.call(deposit_account_id:, limit: nil, after_id: nil)
        account = Accounts::Models::DepositAccount.find(deposit_account_id)
        lim = normalized_limit(limit)
        rel = Models::DepositStatement
          .includes(:deposit_product_statement_profile)
          .where(deposit_account_id: account.id)
        rel = rel.where("id < ?", after_id.to_i) if after_id.present?

        fetched = rel.order(id: :desc).limit(lim + 1).to_a
        has_more = fetched.size > lim
        rows = has_more ? fetched.take(lim) : fetched

        Result.new(
          account: account,
          rows: rows,
          next_after_id: has_more ? rows.last.id : nil,
          has_more: has_more
        )
      end

      def self.normalized_limit(limit)
        return DEFAULT_LIMIT if limit.blank?

        [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min
      end
      private_class_method :normalized_limit
    end
  end
end
