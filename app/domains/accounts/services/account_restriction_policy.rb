# frozen_string_literal: true

module Accounts
  module Services
    module AccountRestrictionPolicy
      module_function

      def active_for(deposit_account_id:)
        Models::AccountRestriction.active.where(deposit_account_id: deposit_account_id)
      end

      def debit_blocking?(deposit_account_id:)
        active_for(deposit_account_id: deposit_account_id)
          .where(restriction_type: Models::AccountRestriction::DEBIT_BLOCKING_TYPES)
          .exists?
      end

      def close_blocking?(deposit_account_id:)
        active_for(deposit_account_id: deposit_account_id)
          .where(restriction_type: Models::AccountRestriction::CLOSE_BLOCKING_TYPES)
          .exists?
      end

      def full_freeze?(deposit_account_id:)
        active_for(deposit_account_id: deposit_account_id)
          .where(restriction_type: Models::AccountRestriction::TYPE_FULL_FREEZE)
          .exists?
      end

      def assert_debit_allowed!(deposit_account_id:)
        return unless debit_blocking?(deposit_account_id: deposit_account_id)

        raise_blocked!("account has an active debit restriction")
      end

      def assert_close_allowed!(deposit_account_id:)
        return unless close_blocking?(deposit_account_id: deposit_account_id)

        raise_blocked!("account has an active close-blocking restriction")
      end

      def assert_routine_servicing_allowed!(deposit_account_id:)
        return unless full_freeze?(deposit_account_id: deposit_account_id)

        raise_blocked!("account has an active full freeze")
      end

      def raise_blocked!(message)
        raise Accounts::Commands::AccountRestricted, message
      end
      private_class_method :raise_blocked!
    end
  end
end
