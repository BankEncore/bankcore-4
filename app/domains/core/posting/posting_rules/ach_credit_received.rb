# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # ACH receipt: settlement asset up, customer DDA liability up (ADR-0028).
      module AchCreditReceived
        ACH_SETTLEMENT_GL = "1120"
        DDA_GL = "2110"

        module_function

        def legs_for(event)
          amount = event.amount_minor_units
          if amount.nil? || amount <= 0
            raise Core::Posting::Commands::PostEvent::InvalidState, "amount_minor_units required"
          end
          if event.source_account_id.blank?
            raise Core::Posting::Commands::PostEvent::InvalidState, "source_account_id required for ach.credit.received"
          end

          [
            PostingLeg.new(
              sequence_no: 1,
              gl_account_number: ACH_SETTLEMENT_GL,
              side: "debit",
              amount_minor_units: amount,
              deposit_account_id: nil
            ),
            PostingLeg.new(
              sequence_no: 2,
              gl_account_number: DDA_GL,
              side: "credit",
              amount_minor_units: amount,
              deposit_account_id: event.source_account_id
            )
          ]
        end
      end
    end
  end
end
