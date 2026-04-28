# frozen_string_literal: true

module Organization
  module Services
    module DefaultOperatingUnit
      INSTITUTION_CODE = "BANKCORE"
      BRANCH_CODE = "MAIN"

      class AmbiguousDefault < StandardError; end
      class NotFound < StandardError; end

      def self.institution
        Models::OperatingUnit.find_by(code: INSTITUTION_CODE)
      end

      def self.branch
        Models::OperatingUnit.find_by(code: BRANCH_CODE) || single_active_branch
      end

      def self.branch!
        branch || raise(NotFound, "default branch operating unit not found")
      end

      def self.single_active_branch
        branches = Models::OperatingUnit.active.branches.limit(2).to_a
        return branches.first if branches.one?
        raise AmbiguousDefault, "multiple active branch operating units require explicit scope" if branches.many?

        nil
      end
    end
  end
end
