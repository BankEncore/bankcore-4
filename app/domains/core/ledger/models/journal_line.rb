# frozen_string_literal: true

module Core
  module Ledger
    module Models
      class JournalLine < ApplicationRecord
        self.table_name = "journal_lines"

        belongs_to :journal_entry, class_name: "Core::Ledger::Models::JournalEntry", inverse_of: :journal_lines
        belongs_to :gl_account, class_name: "Core::Ledger::Models::GlAccount"
        belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount", optional: true
      end
    end
  end
end
