# frozen_string_literal: true

module Accounts
  module Services
    class DepositAccountNumberGenerator
      class SequenceExhausted < StandardError; end

      def self.call(on_date:)
        new(on_date: on_date).call
      end

      def self.valid_luhn?(account_number)
        normalized = account_number.to_s
        return false unless normalized.match?(/\A1\d{11}\z/)

        normalized.reverse.chars.each_with_index.sum do |char, index|
          digit = char.to_i
          if index.odd?
            doubled = digit * 2
            doubled > 9 ? doubled - 9 : doubled
          else
            digit
          end
        end % 10 == 0
      end

      def self.check_digit(base)
        sum = base.to_s.reverse.chars.each_with_index.sum do |char, index|
          digit = char.to_i
          if index.even?
            doubled = digit * 2
            doubled > 9 ? doubled - 9 : doubled
          else
            digit
          end
        end

        (10 - (sum % 10)) % 10
      end

      def initialize(on_date:)
        @on_date = on_date.to_date
      end

      def call
        Models::DepositAccountNumberAllocation.transaction do
          allocation = find_or_create_allocation!
          allocation.lock!
          sequence = allocation.last_sequence + 1
          if sequence > Models::DepositAccountNumberAllocation::MAX_SEQUENCE
            raise SequenceExhausted, "deposit account number sequence exhausted"
          end

          allocation.update!(last_sequence: sequence)
          account_number_for(sequence)
        end
      end

      private

      attr_reader :on_date

      def find_or_create_allocation!
        Models::DepositAccountNumberAllocation.find_by(allocation_key: Models::DepositAccountNumberAllocation::GLOBAL_KEY) ||
          Models::DepositAccountNumberAllocation.create!(allocation_key: Models::DepositAccountNumberAllocation::GLOBAL_KEY)
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def account_number_for(sequence)
        base = "1#{on_date.strftime("%y%m")}#{sequence.to_s.rjust(6, "0")}"
        "#{base}#{self.class.check_digit(base)}"
      end
    end
  end
end
