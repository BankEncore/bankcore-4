# frozen_string_literal: true

module Core
  module Posting
    module Models
      class PostingBatch < ApplicationRecord
        self.table_name = "posting_batches"

        belongs_to :operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent"
        has_many :journal_entries, class_name: "Core::Ledger::Models::JournalEntry", dependent: :restrict_with_exception
      end
    end
  end
end
