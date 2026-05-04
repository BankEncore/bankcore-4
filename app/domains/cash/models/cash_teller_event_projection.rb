# frozen_string_literal: true

module Cash
  module Models
    class CashTellerEventProjection < ApplicationRecord
      self.table_name = "cash_teller_event_projections"

      PROJECTION_TYPE_TELLER_CASH_EVENT = "teller_cash_event"
      PROJECTION_TYPE_TELLER_CASH_REVERSAL = "teller_cash_reversal"
      PROJECTION_TYPES = [
        PROJECTION_TYPE_TELLER_CASH_EVENT,
        PROJECTION_TYPE_TELLER_CASH_REVERSAL
      ].freeze

      belongs_to :operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent"
      belongs_to :reversal_of_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
      belongs_to :teller_session, class_name: "Teller::Models::TellerSession"
      belongs_to :cash_location, class_name: "Cash::Models::CashLocation"

      validates :projection_type, inclusion: { in: PROJECTION_TYPES }
      validates :event_type, :business_date, :applied_at, presence: true
      validates :currency, inclusion: { in: %w[USD] }
      validates :amount_minor_units, numericality: { only_integer: true, greater_than: 0 }
      validates :delta_minor_units, numericality: { only_integer: true, other_than: 0 }
    end
  end
end
