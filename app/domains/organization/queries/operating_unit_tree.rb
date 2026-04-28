# frozen_string_literal: true

module Organization
  module Queries
    module OperatingUnitTree
      def self.call
        Models::OperatingUnit.order(:parent_operating_unit_id, :code)
      end
    end
  end
end
