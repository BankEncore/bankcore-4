# frozen_string_literal: true

module Workspace
  module Models
    class Operator < ApplicationRecord
      self.table_name = "operators"

      ROLES = %w[teller supervisor operations admin].freeze

      has_one :credential, class_name: "Workspace::Models::OperatorCredential", dependent: :destroy

      validates :role, presence: true, inclusion: { in: ROLES }

      def teller?
        role == "teller"
      end

      def supervisor?
        role == "supervisor"
      end

      def operations?
        role == "operations"
      end

      def admin?
        role == "admin"
      end
    end
  end
end
