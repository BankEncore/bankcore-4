# frozen_string_literal: true

module Core
  module Ledger
    module Queries
      # Defensive aggregate: total debits vs total credits for all journal lines on entries
      # with the given business_date. Should always match when every journal is balanced.
      class JournalBalanceCheckForBusinessDate
        Result = Data.define(:total_debit_minor_units, :total_credit_minor_units, :balanced)

        def self.call(business_date:)
          raise ArgumentError, "business_date must be a Date" unless business_date.is_a?(Date)

          base = Models::JournalLine.joins(:journal_entry).where(journal_entries: { business_date: business_date })
          deb = base.where(side: "debit").sum(:amount_minor_units)
          cre = base.where(side: "credit").sum(:amount_minor_units)
          Result.new(
            total_debit_minor_units: deb,
            total_credit_minor_units: cre,
            balanced: deb == cre
          )
        end
      end
    end
  end
end
