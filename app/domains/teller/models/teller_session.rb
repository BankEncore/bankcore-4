# frozen_string_literal: true

module Teller
  module Models
    class TellerSession < ApplicationRecord
      self.table_name = "teller_sessions"

      STATUS_OPEN = "open"
      STATUS_CLOSED = "closed"
      STATUS_PENDING_SUPERVISOR = "pending_supervisor"

      belongs_to :supervisor_operator, class_name: "Workspace::Models::Operator", optional: true
      belongs_to :operating_unit, class_name: "Organization::Models::OperatingUnit"

      has_many :operational_events, class_name: "Core::OperationalEvents::Models::OperationalEvent",
                                    inverse_of: :teller_session,
                                    dependent: :restrict_with_exception

      before_validation :assign_default_operating_unit, on: :create

      private

      def assign_default_operating_unit
        self.operating_unit ||= Organization::Services::DefaultOperatingUnit.branch
      end
    end
  end
end
