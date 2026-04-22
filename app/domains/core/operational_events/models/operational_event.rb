# frozen_string_literal: true

module Core
  module OperationalEvents
    module Models
      class OperationalEvent < ApplicationRecord
        self.table_name = "operational_events"

        STATUS_PENDING = "pending"
        STATUS_POSTED = "posted"

        belongs_to :source_account, class_name: "Accounts::Models::DepositAccount", optional: true

        has_many :posting_batches, class_name: "Core::Posting::Models::PostingBatch", dependent: :restrict_with_exception
        has_many :journal_entries, class_name: "Core::Ledger::Models::JournalEntry", dependent: :restrict_with_exception
      end
    end
  end
end
