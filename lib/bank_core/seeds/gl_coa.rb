# frozen_string_literal: true

module BankCore
  module Seeds
    module GlCoa
      TSV_PATH = Rails.root.join("docs/concepts/100-chart-of-accounts.tsv")

      # Maps TSV "Type" to [account_type, natural_balance] for persistence (ADR-0010 enums).
      TYPE_MAP = {
        "Asset" => %w[asset debit],
        "Contra-Asset" => %w[asset debit],
        "Liability" => %w[liability credit],
        "Equity" => %w[equity credit],
        "Income" => %w[revenue credit],
        "Expense" => %w[expense debit]
      }.freeze

      def self.rows_from_tsv
        lines = File.read(TSV_PATH, encoding: "UTF-8").lines
        header = lines.first
        raise "Unexpected COA header: #{header.inspect}" unless header.start_with?("Account Code\t")

        lines.drop(1).filter_map do |line|
          line = line.chomp
          next if line.empty?

          cols = line.split("\t")
          next if cols.size < 3

          code = cols[0].strip
          name = cols[1].strip
          type = cols[2].strip
          mapped = TYPE_MAP[type] || raise(ArgumentError, "Unknown GL Type #{type.inspect} for account #{code}")

          {
            account_number: code,
            account_type: mapped[0],
            natural_balance: mapped[1],
            account_name: name,
            currency: "USD",
            active: true
          }
        end
      end

      def self.seed!
        rows_from_tsv.each do |attrs|
          Core::Ledger::Models::GlAccount.find_or_initialize_by(account_number: attrs[:account_number]).tap do |a|
            a.assign_attributes(attrs)
            a.save!
          end
        end
      end
    end
  end
end
