# frozen_string_literal: true

module Core
  module Ledger
    module Models
      class JournalEntry < ApplicationRecord
        self.table_name = "journal_entries"

        belongs_to :posting_batch, class_name: "Core::Posting::Models::PostingBatch"
        belongs_to :operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent"
        belongs_to :reverses_journal_entry, class_name: "Core::Ledger::Models::JournalEntry", optional: true
        belongs_to :reversing_journal_entry, class_name: "Core::Ledger::Models::JournalEntry", optional: true

        has_many :journal_lines, class_name: "Core::Ledger::Models::JournalLine", dependent: :restrict_with_exception, inverse_of: :journal_entry
      end
    end
  end
end
