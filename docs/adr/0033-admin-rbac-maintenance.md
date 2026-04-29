# ADR-0033: Admin RBAC maintenance

**Status:** Accepted - first slice implemented  
**Date:** 2026-04-29  
**Decision Type:** Workspace administration / authorization operations  
**Aligns with:** [ADR-0025](0025-internal-workspace-ui.md), [ADR-0029](0029-capability-first-authorization-layer.md), [ADR-0032](0032-operating-units-and-branch-scope.md), [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Context and Problem Statement

BankCORE has database-backed Workspace RBAC tables for operators, roles, capabilities, role-capability mappings, and scoped role assignments. The runtime authorization path reads those database rows through `Workspace::Authorization::CapabilityResolver`, while `Workspace::Authorization::CapabilityRegistry` remains the seed/catalog baseline used by migrations and seed tasks.

Admin staff need an internal HTML maintenance surface for this RBAC data. The first slice should support operational maintenance without changing the financial kernel, adding customer-facing behavior, or creating a new audit subsystem before the admin workflow settles.

---

## 2. Decision Outcome

BankCORE will add an admin-facing HTML RBAC maintenance UI under the existing internal Admin workspace.

The Workspace domain owns the operator and RBAC table family:

- `operators`
- `operator_credentials`
- `roles`
- `capabilities`
- `role_capabilities`
- `operator_role_assignments`

The UI will call `Workspace::Commands` and `Workspace::Queries`; controllers remain workspace-oriented orchestration only.

---

## 3. Invariants

- Runtime authorization uses persisted RBAC rows. The capability registry is the default catalog and seed source, not the direct runtime authorization store.
- `operators.role` remains a legacy compatibility classification. Updating it does not imply automatic destructive rewrites of existing RBAC assignments.
- System roles are viewable and assignable, but they must not be deleted through the admin UI.
- Role and capability records should be deactivated rather than hard-deleted in routine admin workflows.
- Scoped assignments support only global scope or `operating_unit` scope. No region or parent inheritance is implied.
- This slice does not add operational events, posting rules, ledger entries, or financial flows.

---

## 4. Audit Boundary

The first admin RBAC UI slice uses the existing `created_at` and `updated_at` columns as lightweight change evidence. It does not introduce a dedicated Workspace audit log table or new Core operational event types.

A future slice may add durable admin-maintenance audit events after the workflow is exercised and the required evidence model is clearer.

---

## 5. Consequences

- Admin maintenance can keep operators, credentials, role assignments, and role-capability mappings aligned with the database state that authorization actually evaluates.
- Seeded roles and capabilities remain protected by conservative UI behavior rather than a new registry synchronization mechanism.
- The design keeps Workspace administration separate from monetary truth and avoids expanding the Core financial event catalog for non-financial admin changes.
