# frozen_string_literal: true

class CreateRbacTables < ActiveRecord::Migration[8.1]
  class MigrationCapability < ActiveRecord::Base
    self.table_name = "capabilities"
  end

  class MigrationRole < ActiveRecord::Base
    self.table_name = "roles"
  end

  class MigrationRoleCapability < ActiveRecord::Base
    self.table_name = "role_capabilities"
  end

  class MigrationOperator < ActiveRecord::Base
    self.table_name = "operators"
  end

  class MigrationOperatorRoleAssignment < ActiveRecord::Base
    self.table_name = "operator_role_assignments"
  end

  def up
    create_table :capabilities do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :capabilities, :code, unique: true
    add_check_constraint :capabilities, "btrim(code) <> ''", name: "capabilities_code_present_check"
    add_check_constraint :capabilities, "btrim(name) <> ''", name: "capabilities_name_present_check"
    add_check_constraint :capabilities, "btrim(category) <> ''", name: "capabilities_category_present_check"

    create_table :roles do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.boolean :system_role, null: false, default: true
      t.timestamps
    end

    add_index :roles, :code, unique: true
    add_check_constraint :roles, "btrim(code) <> ''", name: "roles_code_present_check"
    add_check_constraint :roles, "btrim(name) <> ''", name: "roles_name_present_check"

    create_table :role_capabilities do |t|
      t.references :role, null: false, foreign_key: true
      t.references :capability, null: false, foreign_key: true
      t.timestamps
    end

    add_index :role_capabilities, [ :role_id, :capability_id ], unique: true,
      name: "index_role_capabilities_on_role_and_capability"

    create_table :operator_role_assignments do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.string :scope_type
      t.bigint :scope_id
      t.boolean :active, null: false, default: true
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end

    add_index :operator_role_assignments, [ :operator_id, :role_id ],
      unique: true,
      where: "scope_type IS NULL AND scope_id IS NULL",
      name: "index_operator_role_assignments_on_global_role"
    add_index :operator_role_assignments, [ :operator_id, :role_id, :scope_type, :scope_id ],
      unique: true,
      where: "scope_type IS NOT NULL AND scope_id IS NOT NULL",
      name: "index_operator_role_assignments_on_scoped_role"
    add_check_constraint :operator_role_assignments,
      "((scope_type IS NULL AND scope_id IS NULL) OR (scope_type IS NOT NULL AND scope_id IS NOT NULL))",
      name: "operator_role_assignments_scope_pair_check"
    add_check_constraint :operator_role_assignments,
      "(starts_at IS NULL OR ends_at IS NULL OR starts_at < ends_at)",
      name: "operator_role_assignments_time_window_check"

    seed_baseline_rbac_data
    backfill_legacy_operator_roles
  end

  def down
    drop_table :operator_role_assignments
    drop_table :role_capabilities
    drop_table :roles
    drop_table :capabilities
  end

  private

  def seed_baseline_rbac_data
    now = Time.current

    Workspace::Authorization::CapabilityRegistry::CAPABILITIES.each do |attrs|
      MigrationCapability.upsert(
        attrs.merge(active: true, created_at: now, updated_at: now),
        unique_by: :index_capabilities_on_code
      )
    end

    Workspace::Authorization::CapabilityRegistry::ROLES.each do |attrs|
      MigrationRole.upsert(
        attrs.merge(active: true, system_role: true, created_at: now, updated_at: now),
        unique_by: :index_roles_on_code
      )
    end

    capability_ids = MigrationCapability.pluck(:code, :id).to_h
    role_ids = MigrationRole.pluck(:code, :id).to_h

    Workspace::Authorization::CapabilityRegistry.role_capability_pairs.each do |pair|
      MigrationRoleCapability.upsert(
        {
          role_id: role_ids.fetch(pair.fetch(:role_code)),
          capability_id: capability_ids.fetch(pair.fetch(:capability_code)),
          created_at: now,
          updated_at: now
        },
        unique_by: :index_role_capabilities_on_role_and_capability
      )
    end
  end

  def backfill_legacy_operator_roles
    now = Time.current
    role_ids = MigrationRole.pluck(:code, :id).to_h

    MigrationOperator.find_each do |operator|
      role_code = Workspace::Authorization::CapabilityRegistry::LEGACY_ROLE_MAPPING[operator.role]
      next if role_code.blank?

      MigrationOperatorRoleAssignment.upsert(
        {
          operator_id: operator.id,
          role_id: role_ids.fetch(role_code),
          scope_type: nil,
          scope_id: nil,
          active: true,
          starts_at: nil,
          ends_at: nil,
          created_at: now,
          updated_at: now
        },
        unique_by: :index_operator_role_assignments_on_global_role
      )
    end
  end
end
