# frozen_string_literal: true

module Workspace
  module Models
    class Operator < ApplicationRecord
      self.table_name = "operators"

      ROLES = %w[teller supervisor].freeze

      validates :role, presence: true, inclusion: { in: ROLES }

      def teller?
        role == "teller"
      end

      def supervisor?
        role == "supervisor"
      end
    end
  end
end
