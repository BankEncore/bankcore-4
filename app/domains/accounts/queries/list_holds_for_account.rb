# frozen_string_literal: true

module Accounts
  module Queries
    class ListHoldsForAccount
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 200
      STATUSES = [
        Models::Hold::STATUS_ACTIVE,
        Models::Hold::STATUS_RELEASED,
        Models::Hold::STATUS_EXPIRED
      ].freeze

      Result = Data.define(:account, :holds, :active_total_minor_units)

      def self.call(deposit_account_id:, status: nil, limit: nil)
        account = Models::DepositAccount.find(deposit_account_id)
        rel = Models::Hold
          .includes(
            :placed_by_operational_event,
            :released_by_operational_event,
            :expired_by_operational_event,
            :placed_for_operational_event
          )
          .where(deposit_account_id: account.id)

        if status.present?
          st = status.to_s
          raise ArgumentError, "unsupported hold status: #{st}" unless STATUSES.include?(st)

          rel = rel.where(status: st)
        end

        holds = rel.to_a.sort_by { |hold| hold_sort_key(hold) }.take(normalized_limit(limit))
        Result.new(
          account: account,
          holds: holds,
          active_total_minor_units: Models::Hold.active_for_account(account.id).sum(:amount_minor_units)
        )
      end

      def self.normalized_limit(limit)
        return DEFAULT_LIMIT if limit.blank?

        [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min
      end
      private_class_method :normalized_limit

      def self.hold_sort_key(hold)
        [
          hold.status == Models::Hold::STATUS_ACTIVE ? 0 : 1,
          -hold.created_at.to_i,
          -hold.id
        ]
      end
      private_class_method :hold_sort_key
    end
  end
end
