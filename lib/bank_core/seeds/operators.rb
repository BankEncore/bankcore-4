# frozen_string_literal: true

module BankCore
  module Seeds
    module Operators
      LOCAL_OPERATORS = [
        { role: "teller", display_name: "Development Teller", username: "dev-teller", password: "password-teller" },
        { role: "supervisor", display_name: "Development Supervisor", username: "dev-supervisor", password: "password-supervisor" },
        { role: "operations", display_name: "Development Operations", username: "dev-operations", password: "password-operations" },
        { role: "admin", display_name: "Development Admin", username: "dev-admin", password: "password-admin" }
      ].freeze

      def self.seed!
        default_operating_unit = Organization::Services::DefaultOperatingUnit.branch

        LOCAL_OPERATORS.each do |attrs|
          operator = Workspace::Models::Operator.find_or_initialize_by(role: attrs.fetch(:role))
          operator.display_name = attrs.fetch(:display_name)
          operator.active = true
          operator.default_operating_unit = default_operating_unit if default_operating_unit.present? &&
            operator.respond_to?(:default_operating_unit=)
          operator.save!

          credential = operator.credential || operator.build_credential
          credential.username = attrs.fetch(:username)
          credential.password = attrs.fetch(:password)
          credential.password_changed_at ||= Time.current
          credential.save!
        end
      end
    end
  end
end
