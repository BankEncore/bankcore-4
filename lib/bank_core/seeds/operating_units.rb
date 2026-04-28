# frozen_string_literal: true

module BankCore
  module Seeds
    module OperatingUnits
      INSTITUTION_CODE = Organization::Services::DefaultOperatingUnit::INSTITUTION_CODE
      BRANCH_CODE = Organization::Services::DefaultOperatingUnit::BRANCH_CODE

      def self.seed!
        institution = Organization::Models::OperatingUnit.find_or_initialize_by(code: INSTITUTION_CODE)
        institution.assign_attributes(
          name: "BankCORE Institution",
          unit_type: Organization::Models::OperatingUnit::UNIT_TYPE_INSTITUTION,
          status: Organization::Models::OperatingUnit::STATUS_ACTIVE,
          time_zone: Rails.application.config.time_zone,
          opened_on: Date.current,
          closed_on: nil
        )
        institution.save!

        branch = Organization::Models::OperatingUnit.find_or_initialize_by(code: BRANCH_CODE)
        branch.assign_attributes(
          name: "Main Branch",
          unit_type: Organization::Models::OperatingUnit::UNIT_TYPE_BRANCH,
          parent_operating_unit: institution,
          status: Organization::Models::OperatingUnit::STATUS_ACTIVE,
          time_zone: Rails.application.config.time_zone,
          opened_on: Date.current,
          closed_on: nil
        )
        branch.save!

        Workspace::Models::Operator.where(default_operating_unit_id: nil).update_all(
          default_operating_unit_id: branch.id,
          updated_at: Time.current
        ) if ActiveRecord::Base.connection.column_exists?(:operators, :default_operating_unit_id)
      end
    end
  end
end
