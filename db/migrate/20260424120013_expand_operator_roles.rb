# frozen_string_literal: true

class ExpandOperatorRoles < ActiveRecord::Migration[8.1]
  ROLES = %w[teller supervisor operations admin].freeze

  def up
    remove_check_constraint :operators, name: "operators_role_check"
    add_check_constraint :operators, role_check_sql, name: "operators_role_check"
  end

  def down
    remove_check_constraint :operators, name: "operators_role_check"
    add_check_constraint :operators, "role IN ('teller', 'supervisor')", name: "operators_role_check"
  end

  private

  def role_check_sql
    quoted_roles = ROLES.map { |role| connection.quote(role) }.join(", ")
    "role IN (#{quoted_roles})"
  end
end
