# frozen_string_literal: true

class AddOverrideApproveCapability < ActiveRecord::Migration[8.1]
  CODE = "override.approve"

  def up
    return unless table_exists?(:capabilities)

    now = Time.current
    cap = Workspace::Models::Capability.find_or_initialize_by(code: CODE)
    cap.assign_attributes(
      name: "Approve override",
      description: "May record override.approved teller-channel control events.",
      category: "control",
      active: true
    )
    cap.save!

    %w[branch_supervisor operations].each do |role_code|
      role = Workspace::Models::Role.find_by(code: role_code)
      next unless role

      Workspace::Models::RoleCapability.find_or_create_by!(role: role, capability: cap)
    end
  end

  def down
    return unless table_exists?(:capabilities)

    cap = Workspace::Models::Capability.find_by(code: CODE)
    return unless cap

    Workspace::Models::RoleCapability.where(capability_id: cap.id).delete_all
    cap.destroy
  end
end
