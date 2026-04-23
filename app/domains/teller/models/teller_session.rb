# frozen_string_literal: true

module Teller
  module Models
    class TellerSession < ApplicationRecord
      self.table_name = "teller_sessions"

      STATUS_OPEN = "open"
      STATUS_CLOSED = "closed"
      STATUS_PENDING_SUPERVISOR = "pending_supervisor"

      belongs_to :supervisor_operator, class_name: "Workspace::Models::Operator", optional: true

      has_many :operational_events, class_name: "Core::OperationalEvents::Models::OperationalEvent",
                                    inverse_of: :teller_session,
                                    dependent: :restrict_with_exception
    end
  end
end
