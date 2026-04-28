# frozen_string_literal: true

module Workspace
  module Models
    class Capability < ApplicationRecord
      self.table_name = "capabilities"

      has_many :role_capabilities, class_name: "Workspace::Models::RoleCapability", dependent: :restrict_with_exception
      has_many :roles, through: :role_capabilities, class_name: "Workspace::Models::Role"

      validates :code, presence: true, uniqueness: true
      validates :name, :category, presence: true
    end
  end
end
