# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # External cash received into vault custody: physical cash increases and due-from settlement decreases.
      module CashShipmentReceived
        CASH_IN_VAULTS_GL = "1110"
        DUE_FROM_CORRESPONDENT_GL = "1130"

        module_function

        def legs_for(event)
          amount = event.amount_minor_units
          if amount.nil? || amount <= 0
            raise Core::Posting::Commands::PostEvent::InvalidState, "amount_minor_units required"
          end

          [
            PostingLeg.new(
              sequence_no: 1,
              gl_account_number: CASH_IN_VAULTS_GL,
              side: "debit",
              amount_minor_units: amount,
              deposit_account_id: nil
            ),
            PostingLeg.new(
              sequence_no: 2,
              gl_account_number: DUE_FROM_CORRESPONDENT_GL,
              side: "credit",
              amount_minor_units: amount,
              deposit_account_id: nil
            )
          ]
        end
      end
    end
  end
end
