# ADR-0029: Capability-first authorization layer

**Status:** Accepted  
**Date:** 2026-04-27  
**Aligns with:** [module catalog](../architecture/bankcore-module-catalog.md) §7, [ADR-0015](0015-teller-workspace-authentication.md), [ADR-0025](0025-internal-workspace-ui.md), [ADR-0026](0026-branch-csr-servicing.md), [ADR-0027](0027-external-read-api-boundary.md), [ADR-0037](0037-internal-staff-authorized-surfaces.md), [roadmap](../roadmap.md) Phase 1G / Phase 4

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

- `deposit.accept`
- `withdrawal.post`
- `transfer.complete`
- `fee.waive`
- `reversal.create`
- `ops.exception.resolve`
- `operational_event.view`
- `audit.export`
- `role.manage`

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

### 2.1 Surfaces vs capabilities

**Capabilities** answer whether an operator may attempt a **category** of action (coarse gate). **Authorized surfaces** answer **where** in staff UIs or APIs that action is exposed—e.g. Branch HTML teller line vs supervisor vs CSR lanes, versus JSON `/teller` ([ADR-0037](0037-internal-staff-authorized-surfaces.md)). Surfaces must still call the same domain commands; they do not duplicate ledger or custody ownership.

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
starts_at
ends_at
created_at
updated_at
```

Scope rules for this ADR:

- `scope_type` and `scope_id` are nullable.
- null scope means institution-wide assignment.
- ADR-0032 introduces the first concrete scoped value: `scope_type = "operating_unit"` and `scope_id = operating_units.id`.
- `Workspace::Authorization::CapabilityResolver` evaluates active global assignments plus exact-match active operating-unit assignments when an operating-unit scope is supplied.
- scoped authorization is exact-match only in this slice; parent, region, department, or branch hierarchy inheritance requires a future ADR.
- scope values other than `operating_unit` are invalid until another accepted ADR defines them.

Temporal rules:

- `starts_at` and `ends_at` are nullable `datetime` columns.
- `starts_at: nil` means the assignment is eligible immediately.
- `ends_at: nil` means the assignment has no scheduled end.
- an assignment is effective when `active = true`, `starts_at` is nil or `starts_at <= Time.current`, and `ends_at` is nil or `Time.current < ends_at`.
- `ends_at` is exclusive.

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
- capability codes should use the pattern `<object>.<action>`
- capability actions should be present-tense authority verbs, while operational events remain past-tense business facts
- when a capability protects an action that records an operational event, prefer the same business object noun as the event type

Examples:

```text
Operational event: deposit.accepted
Capability:        deposit.accept

Operational event: fee.waived
Capability:        fee.waive
```

The initial implementation should favor a Ruby `Workspace::Authorization::CapabilityRegistry` as the source for baseline capability definitions and role bundles. Migrations and seeds may use the registry to create database rows, but the registry remains the code-reviewed source for baseline RBAC data. Role-management UI is deferred.

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

If operating-unit scope is present:
  return capabilities assigned through active, unexpired, globally scoped operator role assignments.
  Also return active, unexpired assignments where scope_type = "operating_unit"
  and scope_id exactly matches the supplied operating unit.
```

Operators may expose a convenience method:

```ruby
current_operator.has_capability?("reversal.create", scope: current_authorization_scope)
```

Convenience methods must delegate to the resolver and must not duplicate role/capability traversal logic.

### 6.1 Command-layer enforcement

Controllers may perform capability checks for navigation, button visibility, redirects, and friendly `403` responses, but controller authorization is not sufficient for privileged writes.

Control-sensitive commands must enforce required capabilities at the command boundary. This applies to commands that waive fees, place or release holds, create reversals, close the business date, approve teller-session variances, maintain authorized signers, or perform similarly privileged state changes.

Commands should:

- accept `actor_id` as the durable staff actor reference
- resolve `actor_id` to an active `Workspace::Models::Operator`
- call `Workspace::Authorization::CapabilityResolver`
- fail closed when the actor is missing, inactive, or lacks the required capability
- avoid direct traversal of role or capability tables outside the Workspace resolver

Business rules and conditional controls remain in the owning command, policy, or domain service. For example, a command may require `reversal.create`, but reversal age, linked-hold guards, source-event status, idempotency replay, and no-self-approval checks remain explicit non-RBAC controls.

---

## 7. Compatibility Strategy

Existing role helpers may remain temporarily:

```ruby
current_operator.teller?
current_operator.supervisor?
current_operator.operations?
current_operator.admin?
```

These helpers should remain legacy compatibility helpers during migration. They must not be redefined as aliases for one action-specific capability such as `business_date.close`, because a role and a capability are not equivalent.

New control-sensitive checks should use capabilities directly:

```ruby
current_operator.has_capability?("reversal.create")
current_operator.has_capability?("fee.waive")
```

The migration path is:

1. create capability and role tables
2. create baseline capabilities and role bundles through migration
3. backfill role assignments from `operators.role` through migration
4. keep `operators.role` temporarily for compatibility
5. migrate one control-sensitive check at a time
6. add regression tests before replacing each legacy role check
7. decide in a later ADR whether `operators.role` is removed, retained as display-only, or retained as a default role-template hint

This avoids a big-bang authorization refactor.

Production deploys must not depend on running seeds to preserve authorization behavior. The initial RBAC migrations must create the baseline capability rows, role rows, role-capability links, and global `operator_role_assignments` derived from existing `operators.role` values before any shipped role check is replaced by a capability check.

Seeds remain useful for development, test, local rebuilds, and idempotent repair, but later role-management or institution-specific configuration must not rely on rerunning seeds. The compatibility backfill should create missing global assignments conservatively and preserve `operators.role` unchanged; it must not delete future assignments or reconcile institution-specific changes.

Response contracts should remain stable during the migration. Existing Teller JSON errors and Branch redirect/flash behavior may continue to use legacy role-oriented wording such as "supervisor role required" while the underlying check moves to capabilities. Capability-neutral wording such as "Not authorized for this action" can be introduced later as a separate UI/API cleanup after compatibility role checks are retired.

Role-management UI is deferred, but admin-managed RBAC must not ship without audit evidence. Future role assignment change records should capture, at minimum, actor, target operator, role, affected assignment, action, old and new active state, old and new `starts_at` / `ends_at`, reason, and timestamp.

---

## 8. Baseline Role Bundles

Initial seeded role bundles must preserve existing behavior. The table below is a baseline, not an institution-specific final matrix.

| Capability | Teller | Branch Supervisor | CSR | Branch Manager | Operations | Auditor | System Admin |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `deposit.accept` | Yes | Yes | No | No | No | No | No |
| `withdrawal.post` | Yes | Yes | No | No | No | No | No |
| `transfer.complete` | Yes | Yes | No | No | No | No | No |
| `teller_session.open` | Yes | Yes | No | No | No | No | No |
| `teller_session.close` | Yes | Yes | No | No | No | No | No |
| `cash_drawer.manage` | Yes | Yes | No | No | No | No | No |
| `party.create` | Yes | Yes | Yes | Yes | No | No | No |
| `account.open` | Yes | Yes | Yes | Yes | No | No | No |
| `account.maintain` | No | Yes | Yes | Yes | No | No | No |
| `hold.place` | Yes | Yes | Yes | Yes | No | No | No |
| `fee.waive` | No | Yes | No | Yes | No | No | No |
| `hold.release` | No | Yes | No | Yes | No | No | No |
| `business_date.close` | No | Yes | No | No | Yes | No | No |
| `teller_session_variance.approve` | No | Yes | No | No | Yes | No | No |
| `reversal.create` | No | Yes | No | Yes | No | No | No |
| `ops.batch.process` | No | No | No | No | Yes | No | No |
| `ops.exception.resolve` | No | No | No | No | Yes | No | No |
| `ops.reconciliation.perform` | No | No | No | No | Yes | No | No |
| `operational_event.view` | No | Yes | Yes | Yes | Yes | Yes | Yes |
| `journal_entry.view` | No | No | No | Yes | Yes | Yes | No |
| `audit.export` | No | No | No | No | Yes | Yes | No |
| `report.view` | Limited | Yes | Yes | Yes | Yes | Yes | Yes |
| `user.manage` | No | No | No | No | No | No | Yes |
| `role.manage` | No | No | No | No | No | No | Yes |
| `system.configure` | No | No | No | No | No | No | Yes |

System administrators do not receive financial approval capabilities by default. If a bank needs emergency financial authority for technology administrators, that must be modeled as a separate break-glass role with explicit audit and review requirements.

`branch_supervisor` is the compatibility target for existing `operators.role = supervisor` records and should preserve today's migrated supervisor behavior. `csr`, `branch_manager`, and `auditor` are seeded future-facing bundles and existing operators are not backfilled into them unless development or test seed data explicitly creates those users.

`operations` receives `business_date.close` and `teller_session_variance.approve` to preserve the shipped Ops control surfaces while Teller JSON remains supervisor-equivalent for those same actions.

`system_admin` is a technology administration role, not a financial approval role. Support visibility through `operational_event.view` and `report.view` does not imply authority to waive fees, release holds, create reversals, close the business date, or approve teller-session variances.

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
return false unless operator.has_capability?("withdrawal.post")
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
   - to: action-specific capabilities such as `current_operator.has_capability?("teller_session_variance.approve")`

2. Reversal approval
   - from: supervisor-only checks
   - to: `current_operator.has_capability?("reversal.create")`

3. Fee waiver
   - from: hardcoded supervisor check
   - to: `current_operator.has_capability?("fee.waive")`

4. Admin role management, once role-management UI exists
   - from: `current_operator.admin?`
   - to: `current_operator.has_capability?("role.manage")`

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
2. Should the Ruby capability registry later be supplemented with institution-specific role configuration outside code?
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
