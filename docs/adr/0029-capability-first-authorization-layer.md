# ADR-0029: Capability-first authorization layer

**Status:** Proposed  
**Date:** 2026-04-27  
**Aligns with:** [module catalog](../architecture/bankcore-module-catalog.md) §7, [ADR-0015](0015-teller-workspace-authentication.md), [ADR-0025](0025-internal-workspace-ui.md), [ADR-0026](0026-branch-csr-servicing.md), [ADR-0027](0027-external-read-api-boundary.md), [roadmap](../roadmap.md) Phase 1G / Phase 4

---

## 1. Context

BankCORE currently uses a narrow staff authorization model based on one role value on each operator:

```text
operators.role = teller | supervisor | operations | admin
```

This has been sufficient for early teller, Branch, Ops, and Admin slices, but it is becoming too limited for BankCORE's operating model.

Authorization decisions now vary by:

- workspace
- transaction or event type
- approval authority
- future branch, location, or operating-unit scope
- teller session state
- cash location
- amount threshold
- account status and restrictions
- dual-control requirements
- segregation-of-duties rules
- audit, reporting, and export access

The current model pushes controls into scattered checks such as:

```ruby
current_operator.supervisor?
current_operator.admin?
```

BankCORE already has the right anchors for a richer staff authorization layer:

- `Workspace::Models::Operator` is the canonical internal staff actor.
- `operational_events.actor_id` provides durable audit attribution.
- internal workspaces already separate Branch, Ops, and Admin surfaces.
- teller activity already has session controls.
- approval, reversal, fee-waiver, authorized-signer maintenance, and exception workflows need more precise authority than a single role string.

Decision drivers:

- preserve the existing actor identity and audit model
- reduce hardcoded role checks in control-sensitive code
- allow one operator to hold more than one authority bundle
- prepare for scoped staff authority without finalizing the branch/location model in this ADR
- keep capabilities separate from transaction-specific business rules
- preserve existing behavior during migration
- keep customer, partner, and external API authorization separate from internal staff authorization

---

## 2. Decision

BankCORE will adopt a capability-first authorization layer for internal staff operators.

Authorization will be modeled as:

```text
Operator
  -> OperatorRoleAssignment
  -> Role
  -> RoleCapability
  -> Capability
```

`Workspace` owns staff authorization persistence and resolution. Other domains may ask authorization questions, but they must not own separate role or capability tables.

The existing role values (`teller`, `supervisor`, `operations`, `admin`) are legacy compatibility roles. They will be migrated into seeded role bundles that preserve current behavior before any existing role gates are removed.

Capabilities answer:

```text
May this internal staff operator attempt this category of action?
```

Examples:

- `txn.cash.deposit`
- `txn.cash.withdrawal`
- `txn.override.fee`
- `approval.standard`
- `approval.reversal`
- `ops.exception.resolve`
- `audit.operational_events.view`
- `audit.export`
- `admin.role.manage`

Capabilities must not encode conditional controls.

Examples of rules that remain outside capabilities:

- transaction limits
- approval thresholds
- active teller session requirements
- available-balance and hold rules
- account restrictions
- self-approval prevention
- dual-control requirements
- business-date rules
- reversal age, amount, and source-event status rules
- future branch-specific transaction state

Those checks belong in policy, command, transaction-code, approval-rule, workflow, and domain validation layers.

---

## 3. Scope

This ADR covers:

- staff operator authorization
- role/capability relationship
- capability registry expectations
- migration away from single hardcoded role checks
- compatibility with future scoped RBAC
- distinction between capabilities and conditional controls

This ADR does not define:

- the full branch, location, or operating-unit model
- branch-scoped business date behavior
- approval threshold engine
- teller session balancing rules
- product configuration rules
- full Pundit adoption
- UI design for role management
- customer portal, partner API, fintech API, ACH participant, wire, card, or external identity authorization

ADR-0027 remains authoritative for external API identity and authorization boundaries.

---

## 4. Data Model

### 4.1 `capabilities`

Stores canonical atomic permission codes.

```text
id
code
name
description
category
active
created_at
updated_at
```

Rules:

- `code` is unique.
- codes are stable internal API and must not be renamed casually.
- seeded capability codes must be documented in a canonical registry.
- code references in controllers, commands, views, and tests must not drift from the registry.

Initial categories may include:

- `transaction`
- `override`
- `approval`
- `teller`
- `cash`
- `party`
- `account`
- `operations`
- `audit`
- `reporting`
- `admin`

### 4.2 `roles`

Stores named role bundles.

```text
id
code
name
description
active
system_role
created_at
updated_at
```

Seeded initial role bundles:

| Code | Name |
| --- | --- |
| `teller` | Teller |
| `branch_supervisor` | Branch Supervisor |
| `operations` | Operations |
| `system_admin` | System Administrator |

`system_role` means the seeded role is part of BankCORE's baseline and should not be deleted by routine role-management UI.

### 4.3 `role_capabilities`

Join table between roles and capabilities.

```text
id
role_id
capability_id
created_at
updated_at
```

Uniqueness:

```text
unique(role_id, capability_id)
```

### 4.4 `operator_role_assignments`

Assigns roles to operators.

```text
id
operator_id
role_id
scope_type
scope_id
active
starts_on
ends_on
created_at
updated_at
```

Scope rules for this ADR:

- `scope_type` and `scope_id` are nullable.
- null scope means institution-wide assignment for the current narrow implementation.
- future ADRs may define scoped values such as `branch`, `location`, or `operating_unit`.
- until those scope models exist, implementation must not invent branch resolution rules.

Uniqueness:

```text
unique(operator_id, role_id, scope_type, scope_id)
```

If PostgreSQL null semantics make that index insufficient for global assignments, add a partial unique index for rows where `scope_type IS NULL AND scope_id IS NULL`.

---

## 5. Capability Registry

BankCORE must maintain a canonical capability registry.

The registry may be implemented as seed data, YAML, database rows, or a combination, but there must be one authoritative source for baseline capability codes.

Rules:

- every seeded role capability must refer to a registered capability code
- code references in application code must be covered by tests or registry checks
- deleting or renaming a capability requires an explicit migration plan
- institution-specific role bundles may compose registered capabilities, but must not create undeclared codes at runtime

The initial implementation should favor seed-managed baseline capabilities and role bundles. Role-management UI is deferred.

---

## 6. Capability Resolution

BankCORE will expose a resolver owned by `Workspace`, for example:

```ruby
Workspace::Authorization::CapabilityResolver.capabilities_for(operator:, scope: nil)
```

The resolver returns active capability codes for the operator in the current authorization scope.

Initial behavior:

```text
If scope is nil:
  return capabilities assigned through active, unexpired, globally scoped operator role assignments.

If scope is present:
  return globally scoped capabilities plus capabilities for matching scope_type/scope_id,
  once a future scoped-RBAC ADR defines valid scope resolution.
```

Operators may expose a convenience method:

```ruby
current_operator.has_capability?("approval.standard", scope: current_authorization_scope)
```

Convenience methods must delegate to the resolver and must not duplicate role/capability traversal logic.

---

## 7. Compatibility Strategy

Existing role helpers may remain temporarily:

```ruby
current_operator.teller?
current_operator.supervisor?
current_operator.operations?
current_operator.admin?
```

These helpers should remain legacy compatibility helpers during migration. They must not be redefined as aliases for one broad capability such as `approval.standard`, because a role and a capability are not equivalent.

New control-sensitive checks should use capabilities directly:

```ruby
current_operator.has_capability?("approval.standard")
current_operator.has_capability?("txn.override.fee")
```

The migration path is:

1. create capability and role tables
2. seed baseline capabilities and role bundles
3. backfill role assignments from `operators.role`
4. keep `operators.role` temporarily for compatibility
5. migrate one control-sensitive check at a time
6. add regression tests before replacing each legacy role check
7. decide in a later ADR whether `operators.role` is removed, retained as display-only, or retained as a default role-template hint

This avoids a big-bang authorization refactor.

---

## 8. Baseline Role Bundles

Initial seeded role bundles must preserve existing behavior. The table below is a baseline, not an institution-specific final matrix.

| Capability | Teller | Branch Supervisor | Operations | System Admin |
| --- | ---: | ---: | ---: | ---: |
| `txn.cash.deposit` | Yes | Yes | No | No |
| `txn.cash.withdrawal` | Yes | Yes | No | No |
| `txn.cash.check_cashing` | Yes | Yes | No | No |
| `txn.cash.bank_draft.issue` | Yes | Yes | No | No |
| `txn.transfer.internal` | Yes | Yes | No | No |
| `teller.session.open` | Yes | Yes | No | No |
| `teller.session.close` | Yes | Yes | No | No |
| `teller.cash.manage_drawer` | Yes | Yes | No | No |
| `txn.override.fee` | No | Yes | No | No |
| `txn.override.hold` | No | Yes | No | No |
| `approval.standard` | No | Yes | No | No |
| `approval.reversal` | No | Yes | No | No |
| `ops.exception.resolve` | No | No | Yes | No |
| `ops.reconciliation.perform` | No | No | Yes | No |
| `ops.batch.process` | No | No | Yes | No |
| `audit.operational_events.view` | No | Limited | Yes | Yes |
| `audit.posting.view` | No | No | Yes | Yes |
| `audit.export` | No | No | Yes | No |
| `reporting.view` | No | Limited | Yes | Yes |
| `admin.user.manage` | No | No | No | Yes |
| `admin.role.manage` | No | No | No | Yes |
| `admin.system.configure` | No | No | No | Yes |

System administrators do not receive financial approval capabilities by default. If a bank needs emergency financial authority for technology administrators, that must be modeled as a separate break-glass role with explicit audit and review requirements.

---

## 9. Conditional Controls

Capabilities are necessary but not sufficient.

| Control | Example |
| --- | --- |
| Amount threshold | Teller may initiate withdrawal, but approval is required above a limit. |
| Active session | Teller cash transaction requires an open teller session. |
| Available balance | Withdrawal requires sufficient available funds under the account's authorization rules. |
| No self-approval | Approver cannot approve an event they initiated. |
| Dual control | Vault access requires two authorized actors. |
| Business date | Posting requires a valid open business date. |
| Account restrictions | Dormant, frozen, restricted, or closed accounts may block action. |
| Reversal controls | Reversal may depend on age, amount, source event status, and linked holds. |

Example:

```ruby
return false unless operator.has_capability?("txn.cash.withdrawal")
return false unless teller_session.open?
return false unless available_balance_minor_units >= amount_minor_units
return approval_required if amount_minor_units > threshold_minor_units
```

The capability only answers whether the operator may attempt the action category. The remaining checks decide whether this specific action is currently allowed, denied, or requires approval.

---

## 10. First Migration Targets

The first implementation slice should migrate a small number of high-control checks.

Recommended targets:

1. Standard approval
   - from: `current_operator.supervisor?`
   - to: `current_operator.has_capability?("approval.standard")`

2. Reversal approval
   - from: supervisor-only checks
   - to: `current_operator.has_capability?("approval.reversal")`

3. Fee waiver
   - from: hardcoded supervisor check
   - to: `current_operator.has_capability?("txn.override.fee")`

4. Admin role management, once role-management UI exists
   - from: `current_operator.admin?`
   - to: `current_operator.has_capability?("admin.role.manage")`

Broad workspace navigation should not be the first migration target. Domain controls are easier to test and carry clearer audit/control value.

---

## 11. Consequences

Positive:

- supports scoped staff RBAC without replacing the actor model
- allows institution-specific role bundles
- reduces scattered hardcoded role checks
- separates authority from transaction-specific conditions
- supports future approval queues and threshold engines
- improves audit defensibility
- allows one operator to hold different roles in different scopes later
- aligns with BankCORE's modular monolith and event-driven control model

Negative:

- adds authorization tables and seed data
- requires a resolver layer
- creates a migration period with both `operators.role` and role assignments
- requires more authorization regression tests
- increases the risk of configuration mistakes if role-management UI is added too early

Neutral:

- Pundit may be adopted later, but this ADR does not require it.
- Branch scope is prepared structurally but not activated until a branch/location ADR defines resolution rules.

---

## 12. Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Over-modeling before branch/location scope is finalized | Use nullable generic scope and treat null as global until a future ADR defines scoped resolution. |
| Treating capabilities as business rules | Keep thresholds, sessions, dual control, and account state in policy/command/workflow layers. |
| Duplicate truth between `operators.role` and role assignments | Treat `operators.role` as compatibility-only after backfill and migrate one check at a time. |
| Accidentally broadening access | Seed bundles to preserve current behavior and add regression tests for every migrated gate. |
| Capability-code drift | Maintain a canonical registry and test code references against it. |
| Admins gaining financial power by accident | Do not grant financial approval capabilities to `system_admin` by default. |
| Ambiguous audit access | Split audit view, posting view, export, and reporting capabilities. |

---

## 13. Open Questions

1. Should `operators.role` eventually be removed, retained as display-only, or retained as a default role-template hint?
2. Should the canonical capability registry be database-first, YAML-first, or seed-managed with drift tests?
3. Should institution-specific role bundles be editable in the UI during MVP, or remain seed/config managed?
4. Which scoped assignment types should be valid after branch/location modeling: `branch`, `location`, `operating_unit`, or something else?
5. Should workspace navigation become capability-driven immediately, or only after control-sensitive domain gates are migrated?
6. How granular should audit capabilities become before compliance reporting is built out?
7. Should authorization context resolution live in a controller concern, `Current`, or a dedicated context object?
8. What audit evidence is required for role and capability assignment changes once role-management UI exists?

---

## 14. Decision Summary

BankCORE will move from a single-role staff authorization model to a capability-first authorization layer.

The implementation preserves `Workspace::Models::Operator` as the canonical staff actor, seeds role bundles equivalent to current behavior, and migrates high-control checks incrementally.

Capabilities determine whether an operator may attempt a category of internal staff action. Conditional controls such as thresholds, active sessions, branch scope, dual control, no-self-approval, business date, available balance, and account state remain explicit policy, workflow, and command-layer rules.
