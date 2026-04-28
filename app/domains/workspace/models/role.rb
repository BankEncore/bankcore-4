# frozen_string_literal: true

module Workspace
  module Models
    class Role < ApplicationRecord
      self.table_name = "roles"

      has_many :role_capabilities, class_name: "Workspace::Models::RoleCapability", dependent: :restrict_with_exception
      has_many :capabilities, through: :role_capabilities, class_name: "Workspace::Models::Capability"
      has_many :operator_role_assignments, class_name: "Workspace::Models::OperatorRoleAssignment",
        dependent: :restrict_with_exception
      has_many :operators, through: :operator_role_assignments, class_name: "Workspace::Models::Operator"

      validates :code, presence: true, uniqueness: true
      validates :name, presence: true
    end
  end
end
