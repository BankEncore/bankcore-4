# frozen_string_literal: true

module Workspace
  module Models
    class RoleCapability < ApplicationRecord
      self.table_name = "role_capabilities"

      belongs_to :role, class_name: "Workspace::Models::Role"
      belongs_to :capability, class_name: "Workspace::Models::Capability"

      validates :role_id, uniqueness: { scope: :capability_id }
    end
  end
end
