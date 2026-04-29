# frozen_string_literal: true

require "test_helper"

class AdminRbacUiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_operator_with_credential!(role: "admin", username: "admin-rbac")
    @branch = Organization::Services::DefaultOperatingUnit.branch
  end

  test "admin can create update deactivate operator and reset credentials" do
    internal_login!(username: "admin-rbac")

    get "/admin/operators"
    assert_response :success
    assert_includes response.body, "Operators"

    get "/admin/operators/new"
    assert_response :success
    assert_includes response.body, "New operator"
    assert_includes response.body, 'name="operator[display_name]"'

    assert_difference -> { Workspace::Models::Operator.count }, 1 do
      post "/admin/operators",
        params: {
          operator: {
            display_name: "HTML Managed Operator",
            role: "teller",
            active: "1",
            default_operating_unit_id: @branch.id,
            username: "html-managed",
            password: "password123"
          }
        }
    end
    operator = Workspace::Models::Operator.order(:id).last
    assert_redirected_to "/admin/operators/#{operator.id}"
    assert_equal "html-managed", operator.credential.username

    get "/admin/operators/#{operator.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit operator"
    assert_includes response.body, 'name="operator[display_name]"'

    patch "/admin/operators/#{operator.id}",
      params: { operator: { display_name: "Updated HTML Operator", role: "supervisor", active: "1" } }
    assert_redirected_to "/admin/operators/#{operator.id}"
    assert_equal "Updated HTML Operator", operator.reload.display_name
    assert_equal "supervisor", operator.role

    post "/admin/operators/#{operator.id}/reset_credential",
      params: { credential: { username: "html-reset", password: "new-password123" } }
    assert_redirected_to "/admin/operators/#{operator.id}"
    assert_equal "html-reset", operator.reload.credential.username

    delete "/logout"
    post "/login", params: { username: "html-reset", password: "new-password123" }
    assert_redirected_to "/internal"

    delete "/logout"
    internal_login!(username: "admin-rbac")
    get "/admin/operators/#{operator.id}"
    assert_response :success
    post "/admin/operators/#{operator.id}/deactivate"
    assert_redirected_to "/admin/operators/#{operator.id}"
    assert_not operator.reload.active?

    delete "/logout"
    post "/login", params: { username: "html-reset", password: "new-password123" }
    assert_response :unauthorized
  end

  test "admin can manage custom role capability matrix and scoped assignments" do
    operator = create_operator_with_credential!(role: "teller", username: "rbac-target")
    capability = Workspace::Models::Capability.find_by!(
      code: Workspace::Authorization::CapabilityRegistry::AUDIT_EXPORT
    )

    internal_login!(username: "admin-rbac")

    get "/admin/roles/new"
    assert_response :success
    assert_includes response.body, "New role"
    assert_includes response.body, 'name="role[name]"'

    post "/admin/roles",
      params: {
        role: {
          code: "html_role_#{SecureRandom.hex(4)}",
          name: "HTML Role",
          active: "1"
        },
        capability_ids: [ capability.id ]
      }
    role = Workspace::Models::Role.order(:id).last
    assert_redirected_to "/admin/roles/#{role.id}"
    assert_includes role.capabilities, capability

    get "/admin/operators/#{operator.id}/operator_role_assignments/new"
    assert_response :success
    assert_includes response.body, "Assign role"
    assert_includes response.body, 'name="operator_role_assignment[role_id]"'

    get "/admin/roles/#{role.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit role"
    assert_includes response.body, 'name="role[name]"'

    patch "/admin/roles/#{role.id}",
      params: { role: { name: "Updated HTML Role", description: "Edited through admin UI", active: "1" } }
    assert_redirected_to "/admin/roles/#{role.id}"
    assert_equal "Updated HTML Role", role.reload.name

    post "/admin/operators/#{operator.id}/operator_role_assignments",
      params: {
        operator_role_assignment: {
          role_id: role.id,
          scope_type: "operating_unit",
          scope_id: @branch.id,
          active: "1"
        }
      }
    assert_redirected_to "/admin/operators/#{operator.id}"
    assert operator.has_capability?(Workspace::Authorization::CapabilityRegistry::AUDIT_EXPORT, scope: @branch)
    assignment = operator.operator_role_assignments.order(:id).last

    get "/admin/operators/#{operator.id}"
    assert_response :success
    assert_includes response.body, Workspace::Authorization::CapabilityRegistry::AUDIT_EXPORT

    get "/admin/operators/#{operator.id}/operator_role_assignments/#{assignment.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit role assignment"
    assert_includes response.body, 'name="operator_role_assignment[role_id]"'

    patch "/admin/roles/#{role.id}/capabilities", params: { capability_ids: [] }
    assert_redirected_to "/admin/roles/#{role.id}"
    assert_not operator.has_capability?(Workspace::Authorization::CapabilityRegistry::AUDIT_EXPORT, scope: @branch)
  end

  test "admin can manage capabilities and non admin remains forbidden" do
    internal_login!(username: "admin-rbac")

    get "/admin/capabilities/new"
    assert_response :success
    assert_includes response.body, "New capability"
    assert_includes response.body, 'name="capability[name]"'

    assert_difference -> { Workspace::Models::Capability.count }, 1 do
      post "/admin/capabilities",
        params: {
          capability: {
            code: "custom.html.#{SecureRandom.hex(4)}",
            name: "Custom HTML Capability",
            category: "admin",
            active: "1"
          }
        }
    end
    capability = Workspace::Models::Capability.order(:id).last
    assert_redirected_to "/admin/capabilities/#{capability.id}"

    get "/admin/capabilities/#{capability.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit capability"
    assert_includes response.body, 'name="capability[name]"'

    patch "/admin/capabilities/#{capability.id}",
      params: { capability: { name: "Updated Capability", category: "admin", active: "1" } }
    assert_redirected_to "/admin/capabilities/#{capability.id}"
    assert_equal "Updated Capability", capability.reload.name

    post "/admin/capabilities/#{capability.id}/deactivate"
    assert_redirected_to "/admin/capabilities"
    assert_not capability.reload.active?

    delete "/logout"
    create_operator_with_credential!(role: "operations", username: "rbac-non-admin")
    internal_login!(username: "rbac-non-admin")
    get "/admin/operators"
    assert_response :forbidden
  end
end
