# frozen_string_literal: true

module Core
  module OperationalEvents
    module Models
      class OperationalEvent < ApplicationRecord
        self.table_name = "operational_events"

        has_many :posting_batches, class_name: "Core::Posting::Models::PostingBatch", dependent: :restrict_with_exception
        has_many :journal_entries, class_name: "Core::Ledger::Models::JournalEntry", dependent: :restrict_with_exception
      end
    end
  end
end
