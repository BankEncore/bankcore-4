# frozen_string_literal: true

module Teller
  module Commands
    class OpenSession
      class Error < StandardError; end
      class SessionAlreadyOpen < Error; end

      # One open session per operating unit and drawer_code (nil drawer = one unassigned drawer per unit).
      def self.call(drawer_code: nil, operator_id: nil, operating_unit_id: nil)
        operator = Workspace::Models::Operator.find_by(id: operator_id) if operator_id.present?
        operating_unit = Organization::Services::ResolveOperatingUnit.call(
          operator: operator,
          operating_unit_id: operating_unit_id
        )

        Teller::Models::TellerSession.transaction do
          scope = Teller::Models::TellerSession.where(
            status: Teller::Models::TellerSession::STATUS_OPEN,
            operating_unit: operating_unit
          )
          scope = scope.where(drawer_code: drawer_code) if drawer_code.present?
          raise SessionAlreadyOpen, "open session exists for drawer" if scope.exists?

          Teller::Models::TellerSession.create!(
            status: Teller::Models::TellerSession::STATUS_OPEN,
            opened_at: Time.current,
            drawer_code: drawer_code,
            operating_unit: operating_unit
          )
        end
      end
    end
  end
end
