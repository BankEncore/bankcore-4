# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # Signed amount: negative = shortage, positive = overage. ADR-0031.
      module CashVariancePosted
        module_function

        def legs_for(event)
          raw = event.amount_minor_units
          if raw.nil? || raw.to_i == 0
            raise Core::Posting::Commands::PostEvent::InvalidState, "amount_minor_units must be non-zero"
          end

          mag = raw.to_i.abs
          if raw.to_i.negative?
            [
              PostingLeg.new(sequence_no: 1, gl_account_number: "5190", side: "debit", amount_minor_units: mag, deposit_account_id: nil),
              PostingLeg.new(sequence_no: 2, gl_account_number: "1110", side: "credit", amount_minor_units: mag, deposit_account_id: nil)
            ]
          else
            [
              PostingLeg.new(sequence_no: 1, gl_account_number: "1110", side: "debit", amount_minor_units: mag, deposit_account_id: nil),
              PostingLeg.new(sequence_no: 2, gl_account_number: "5190", side: "credit", amount_minor_units: mag, deposit_account_id: nil)
            ]
          end
        end
      end
    end
  end
end
