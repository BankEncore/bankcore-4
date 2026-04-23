# frozen_string_literal: true

module Core
  module Ledger
    module Queries
      # Activity-only trial balance: one row per GL account with non-zero debits or credits
      # for journal entries on the given business_date (see ADR-0016).
      class TrialBalanceForBusinessDate
        Row = Data.define(
          :gl_account_id,
          :account_number,
          :account_name,
          :account_type,
          :debit_minor_units,
          :credit_minor_units
        )

        def self.call(business_date:)
          raise ArgumentError, "business_date must be a Date" unless business_date.is_a?(Date)

          sql = <<~SQL.squish
            SELECT gl_accounts.id AS gl_account_id,
                   gl_accounts.account_number,
                   gl_accounts.account_name,
                   gl_accounts.account_type,
                   COALESCE(SUM(CASE WHEN journal_lines.side = 'debit'
                                THEN journal_lines.amount_minor_units ELSE 0 END), 0)::bigint AS debit_minor_units,
                   COALESCE(SUM(CASE WHEN journal_lines.side = 'credit'
                                THEN journal_lines.amount_minor_units ELSE 0 END), 0)::bigint AS credit_minor_units
            FROM journal_lines
            INNER JOIN journal_entries ON journal_entries.id = journal_lines.journal_entry_id
            INNER JOIN gl_accounts ON gl_accounts.id = journal_lines.gl_account_id
            WHERE journal_entries.business_date = ?
            GROUP BY gl_accounts.id, gl_accounts.account_number, gl_accounts.account_name, gl_accounts.account_type
            HAVING COALESCE(SUM(CASE WHEN journal_lines.side = 'debit'
                              THEN journal_lines.amount_minor_units ELSE 0 END), 0) > 0
                OR COALESCE(SUM(CASE WHEN journal_lines.side = 'credit'
                              THEN journal_lines.amount_minor_units ELSE 0 END), 0) > 0
            ORDER BY gl_accounts.account_number
          SQL

          ActiveRecord::Base.connection.select_all(
            ActiveRecord::Base.sanitize_sql_array([ sql, business_date ])
          ).map do |h|
            Row.new(
              gl_account_id: h["gl_account_id"].to_i,
              account_number: h["account_number"],
              account_name: h["account_name"],
              account_type: h["account_type"],
              debit_minor_units: h["debit_minor_units"].to_i,
              credit_minor_units: h["credit_minor_units"].to_i
            )
          end
        end
      end
    end
  end
end
