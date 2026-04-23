# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # Internal transfer: Dr 2110 from source, Cr 2110 to destination (subledger on both legs).
      module TransferCompleted
        module_function

        def legs_for(event)
          amount = event.amount_minor_units
          if amount.nil? || amount <= 0
            raise Core::Posting::Commands::PostEvent::InvalidState, "amount_minor_units required"
          end
          if event.source_account_id.blank? || event.destination_account_id.blank?
            raise Core::Posting::Commands::PostEvent::InvalidState,
                  "source_account_id and destination_account_id required for transfer.completed"
          end
          if event.source_account_id == event.destination_account_id
            raise Core::Posting::Commands::PostEvent::InvalidState, "transfer requires two distinct accounts"
          end

          [
            PostingLeg.new(
              sequence_no: 1,
              gl_account_number: "2110",
              side: "debit",
              amount_minor_units: amount,
              deposit_account_id: event.source_account_id
            ),
            PostingLeg.new(
              sequence_no: 2,
              gl_account_number: "2110",
              side: "credit",
              amount_minor_units: amount,
              deposit_account_id: event.destination_account_id
            )
          ]
        end
      end
    end
  end
end
