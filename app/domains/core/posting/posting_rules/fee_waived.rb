# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # Reverses fee.assessed economically: Dr income / Cr DDA liability (ADR-0019).
      module FeeWaived
        module_function

        def legs_for(event)
          amount = event.amount_minor_units
          if amount.nil? || amount <= 0
            raise Core::Posting::Commands::PostEvent::InvalidState, "amount_minor_units required"
          end
          if event.source_account_id.blank?
            raise Core::Posting::Commands::PostEvent::InvalidState, "source_account_id required for fee.waived"
          end

          [
            PostingLeg.new(
              sequence_no: 1,
              gl_account_number: "4510",
              side: "debit",
              amount_minor_units: amount,
              deposit_account_id: nil
            ),
            PostingLeg.new(
              sequence_no: 2,
              gl_account_number: "2110",
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
