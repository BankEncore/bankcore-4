# frozen_string_literal: true

class CreateOperatingUnitsAndScopeRefs < ActiveRecord::Migration[8.1]
  class MigrationOperatingUnit < ActiveRecord::Base
    self.table_name = "operating_units"
  end

  class MigrationOperator < ActiveRecord::Base
    self.table_name = "operators"
  end

  class MigrationTellerSession < ActiveRecord::Base
    self.table_name = "teller_sessions"
  end

  class MigrationOperationalEvent < ActiveRecord::Base
    self.table_name = "operational_events"
  end

  INSTITUTION_CODE = "BANKCORE"
  BRANCH_CODE = "MAIN"
  UNIT_TYPES = %w[institution branch operations department region].freeze
  STATUSES = %w[active inactive closed].freeze

  def up
    create_table :operating_units do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :unit_type, null: false
      t.references :parent_operating_unit, null: true, foreign_key: { to_table: :operating_units }
      t.string :status, null: false, default: "active"
      t.string :time_zone, null: false, default: "Eastern Time (US & Canada)"
      t.date :opened_on
      t.date :closed_on
      t.timestamps
    end

    add_index :operating_units, :code, unique: true
    add_check_constraint :operating_units, "btrim(code) <> ''", name: "operating_units_code_present_check"
    add_check_constraint :operating_units, "btrim(name) <> ''", name: "operating_units_name_present_check"
    add_check_constraint :operating_units, in_list_sql("unit_type", UNIT_TYPES), name: "operating_units_unit_type_check"
    add_check_constraint :operating_units, in_list_sql("status", STATUSES), name: "operating_units_status_check"
    add_check_constraint :operating_units,
      "parent_operating_unit_id IS NULL OR parent_operating_unit_id <> id",
      name: "operating_units_parent_not_self_check"
    add_check_constraint :operating_units,
      "status <> 'closed' OR closed_on IS NOT NULL",
      name: "operating_units_closed_on_required_check"

    seed_default_units

    add_reference :operators, :default_operating_unit, null: true, foreign_key: { to_table: :operating_units }
    add_reference :teller_sessions, :operating_unit, null: true, foreign_key: { to_table: :operating_units }
    add_reference :operational_events, :operating_unit, null: true, foreign_key: { to_table: :operating_units }
    add_check_constraint :operator_role_assignments,
      "scope_type IS NULL OR scope_type = 'operating_unit'",
      name: "operator_role_assignments_scope_type_check"

    backfill_scope_references

    change_column_null :teller_sessions, :operating_unit_id, false
  end

  def down
    remove_check_constraint :operator_role_assignments, name: "operator_role_assignments_scope_type_check"
    remove_reference :operational_events, :operating_unit, foreign_key: { to_table: :operating_units }
    remove_reference :teller_sessions, :operating_unit, foreign_key: { to_table: :operating_units }
    remove_reference :operators, :default_operating_unit, foreign_key: { to_table: :operating_units }
    drop_table :operating_units
  end

  private

  def seed_default_units
    now = Time.current
    today = Date.current

    MigrationOperatingUnit.create!(
      code: INSTITUTION_CODE,
      name: "BankCORE Institution",
      unit_type: "institution",
      status: "active",
      time_zone: "Eastern Time (US & Canada)",
      opened_on: today,
      created_at: now,
      updated_at: now
    )

    institution_id = MigrationOperatingUnit.find_by!(code: INSTITUTION_CODE).id
    MigrationOperatingUnit.create!(
      code: BRANCH_CODE,
      name: "Main Branch",
      unit_type: "branch",
      parent_operating_unit_id: institution_id,
      status: "active",
      time_zone: "Eastern Time (US & Canada)",
      opened_on: today,
      created_at: now,
      updated_at: now
    )
  end

  def backfill_scope_references
    default_branch_id = MigrationOperatingUnit.find_by!(code: BRANCH_CODE).id
    now = Time.current

    MigrationOperator.update_all(default_operating_unit_id: default_branch_id, updated_at: now)
    MigrationTellerSession.update_all(operating_unit_id: default_branch_id, updated_at: now)

    MigrationOperationalEvent.where(channel: %w[teller branch]).update_all(
      operating_unit_id: default_branch_id,
      updated_at: now
    )
  end

  def in_list_sql(column_name, values)
    quoted = values.map { |value| connection.quote(value) }.join(", ")
    "#{column_name} IN (#{quoted})"
  end
end
