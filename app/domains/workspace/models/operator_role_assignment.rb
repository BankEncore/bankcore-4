# frozen_string_literal: true

module Workspace
  module Models
    class OperatorRoleAssignment < ApplicationRecord
      self.table_name = "operator_role_assignments"

      belongs_to :operator, class_name: "Workspace::Models::Operator"
      belongs_to :role, class_name: "Workspace::Models::Role"

      validates :operator_id, uniqueness: {
        scope: :role_id,
        conditions: -> { where(scope_type: nil, scope_id: nil) },
        message: "already has this global role"
      }, if: :global_scope?

      validate :scope_pair_is_complete
      validate :scope_type_is_supported
      validate :operating_unit_scope_exists
      validate :ends_after_starts

      def global_scope?
        scope_type.nil? && scope_id.nil?
      end

      private

      def scope_pair_is_complete
        return if scope_type.present? == scope_id.present?

        errors.add(:scope_id, "must be present with scope_type")
      end

      def scope_type_is_supported
        return if scope_type.blank? || scope_type == "operating_unit"

        errors.add(:scope_type, "must be operating_unit")
      end

      def operating_unit_scope_exists
        return unless scope_type == "operating_unit"
        return if Organization::Models::OperatingUnit.exists?(id: scope_id)

        errors.add(:scope_id, "must reference an operating unit")
      end

      def ends_after_starts
        return if starts_at.blank? || ends_at.blank? || starts_at < ends_at

        errors.add(:ends_at, "must be after starts_at")
      end
    end
  end
end
