# frozen_string_literal: true

module Core
  module OperationalEvents
    module Models
      class OperationalEvent < ApplicationRecord
        self.table_name = "operational_events"

        STATUS_PENDING = "pending"
        STATUS_POSTED = "posted"

        belongs_to :source_account, class_name: "Accounts::Models::DepositAccount", optional: true
        belongs_to :destination_account, class_name: "Accounts::Models::DepositAccount", optional: true
        belongs_to :reversal_of_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
        belongs_to :reversed_by_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
        belongs_to :teller_session, class_name: "Teller::Models::TellerSession", optional: true
        belongs_to :actor, class_name: "Workspace::Models::Operator", foreign_key: :actor_id, optional: true

        has_many :posting_batches, class_name: "Core::Posting::Models::PostingBatch", dependent: :restrict_with_exception
        has_many :journal_entries, class_name: "Core::Ledger::Models::JournalEntry", dependent: :restrict_with_exception
        has_many :reversal_events, class_name: "Core::OperationalEvents::Models::OperationalEvent",
                                   foreign_key: :reversal_of_event_id,
                                   dependent: :restrict_with_exception
      end
    end
  end
end
