# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # Full compensating mirror of the original journal (swap debit/credit per line).
      module PostingReversal
        module_function

        def legs_for(event)
          original = event.reversal_of_event
          if original.nil?
            raise Core::Posting::Commands::PostEvent::InvalidState, "reversal_of_event_id required for posting.reversal"
          end

          orig_entry = original.journal_entries.order(:id).sole
          orig_lines = orig_entry.journal_lines.includes(:gl_account).order(:sequence_no).to_a
          if orig_lines.empty?
            raise Core::Posting::Commands::PostEvent::InvalidState, "original event has no journal lines"
          end

          orig_lines.each_with_index.map do |line, idx|
            mirrored_side = line.side == "debit" ? "credit" : "debit"
            PostingLeg.new(
              sequence_no: idx + 1,
              gl_account_number: line.gl_account.account_number,
              side: mirrored_side,
              amount_minor_units: line.amount_minor_units,
              deposit_account_id: line.deposit_account_id
            )
          end
        end
      end
    end
  end
end
