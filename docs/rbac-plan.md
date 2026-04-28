# RBAC implementation plan

**Status:** Draft  
**Last reviewed:** 2026-04-27  
**Primary ADR:** [ADR-0029: Capability-first authorization layer](adr/0029-capability-first-authorization-layer.md)

This plan uses "RBAC" as shorthand for BankCORE's capability-first staff authorization model. Roles are bundles of capabilities; capabilities are the authorization primitive.

The first implementation must preserve existing behavior while creating a path away from hardcoded checks such as `operator.supervisor?`, `operator.operations?`, and `operator.admin?`.

---

## 1. Goals

- Preserve `Workspace::Models::Operator` as the canonical internal staff actor.
- Keep `operators.role` during migration as compatibility data.
- Add role bundles and capability checks without changing financial outcomes.
- Migrate high-control gates incrementally, with regression tests before each replacement.
- Keep internal staff authorization separate from customer, partner, fintech, ACH participant, wire, card, or external API authorization.

RBAC answers only:

```text
May this internal staff operator attempt this category of action?
```

RBAC must not encode conditional controls.

Examples of rules that remain outside RBAC:

- transaction limits
- approval thresholds
- active teller session checks
- available-balance and hold rules
- account restrictions
- no-self-approval
- dual control
- business-date rules
- reversal age, amount, and source-event status rules
- operating-unit scope rules until ADR-0032 is implemented

---

## 2. Ownership and boundaries

Module owner: `Workspace`.

Workspace owns:

- staff operator identity
- RBAC persistence
- role bundle resolution
- capability resolution
- future scoped staff authority integration

Other domains may ask authorization questions through the Workspace resolver, but they must not own separate role or capability tables.

RBAC does not change `Core::OperationalEvents`, `Core::Posting`, `Core::Ledger`, or `Core::BusinessDate` invariants. It does not introduce new money movement, new posting rules, new reversal semantics, branch-level business dates, or branch-level ledgers.

---

## 3. Role model

Target seeded role bundles:

- `teller`
- `branch_supervisor`
- `csr`
- `branch_manager`
- `operations`
- `auditor`
- `system_admin`

Compatibility mapping from existing roles:

| Existing `operators.role` | Initial role assignment |
| --- | --- |
| `teller` | `teller` |
| `supervisor` | `branch_supervisor` |
| `operations` | `operations` |
| `admin` | `system_admin` |

Seed `csr`, `branch_manager`, and `auditor` roles in the first slice, but do not assign existing operators to them unless a dev/test seed explicitly needs those users.

System administrators must not receive financial approval capabilities by default. If a bank needs emergency financial authority for technology administrators, model it later as a separate break-glass role with explicit audit and review requirements.

---

## 4. Data foundation

Add Workspace-owned tables:

### `capabilities`

Purpose: canonical atomic permission codes.

Columns:

- `code`
- `name`
- `description`
- `category`
- `active`
- timestamps

Constraints:

- unique `code`
- `code` must be stable
- inactive capabilities grant nothing

### `roles`

Purpose: named role bundles.

Columns:

- `code`
- `name`
- `description`
- `active`
- `system_role`
- timestamps

Constraints:

- unique `code`
- inactive roles grant nothing
- `system_role` seeded roles are protected from routine deletion once role management exists

### `role_capabilities`

Purpose: join table between roles and capabilities.

Columns:

- `role_id`
- `capability_id`
- timestamps

Constraints:

- unique pair of `role_id`, `capability_id`

### `operator_role_assignments`

Purpose: assigns role bundles to operators.

Columns:

- `operator_id`
- `role_id`
- `scope_type`
- `scope_id`
- `active`
- `starts_at`
- `ends_at`
- timestamps

Constraints:

- global assignments use `scope_type: nil` and `scope_id: nil`
- add a uniqueness rule for global assignments by `operator_id` and `role_id`
- reserve `scope_type` and `scope_id` for ADR-0032 operating-unit scope, but do not activate scoped resolution in the first RBAC slice
- `starts_at` and `ends_at` are nullable `datetime` columns
- `starts_at: nil` means active immediately
- `ends_at: nil` means no scheduled end
- assignment windows use `starts_at <= Time.current` and `Time.current < ends_at`
- `ends_at` is exclusive

---

## 5. Models and services

Add models:

- `Workspace::Models::Capability`
- `Workspace::Models::Role`
- `Workspace::Models::RoleCapability`
- `Workspace::Models::OperatorRoleAssignment`

Add authorization services:

- `Workspace::Authorization::CapabilityRegistry`
- `Workspace::Authorization::CapabilityResolver`

Add operator convenience methods:

```ruby
operator.capabilities(scope: nil)
operator.has_capability?("reversal.create", scope: nil)
```

The operator methods must delegate to `Workspace::Authorization::CapabilityResolver`. They must not duplicate role traversal logic.

Initial resolver contract:

```ruby
Workspace::Authorization::CapabilityResolver.capabilities_for(operator:, scope: nil)
Workspace::Authorization::CapabilityResolver.has_capability?(operator:, capability_code:, scope: nil)
```

Initial resolver rules:

- inactive operators receive no capabilities
- inactive assignments grant nothing
- assignments outside `starts_at` / `ends_at` grant nothing
- inactive roles grant nothing
- inactive capabilities grant nothing
- unknown capability codes fail closed
- first slice supports global assignments only
- `scope: nil` checks active global assignments only
- `scope: <non-nil>` also checks active global assignments only
- scoped assignment rows grant nothing until ADR-0032 scope resolution is implemented

### Command-layer authorization

Controllers may perform capability checks for workspace navigation, button visibility, redirects, and friendly `403` responses, but controller checks are not sufficient for privileged writes.

Control-sensitive commands must enforce required capabilities at the command boundary. Commands should accept `actor_id`, resolve it to an active `Workspace::Models::Operator`, call `Workspace::Authorization::CapabilityResolver`, and fail closed if the actor is missing, inactive, or lacks the required capability.

Commands must not traverse role or capability tables directly. Other domains may ask authorization questions only through the Workspace resolver.

Business rules and conditional controls remain outside RBAC. For example, a command may require `reversal.create`, but reversal age, linked-hold guards, source-event status, idempotency replay, account status, no-self-approval, and business-date readiness remain explicit domain rules.

---

## 6. Seed and backfill

Add `BankCore::Seeds::Rbac.seed!`.

Production baseline RBAC data and the initial compatibility backfill must be created by migration, not only by seeds. The migration must run before any production code path depends on capability checks and should:

1. Upsert baseline capabilities from the canonical registry.
2. Upsert baseline roles.
3. Upsert role-capability links.
4. Backfill global `operator_role_assignments` from existing `operators.role`.
5. Preserve `operators.role` unchanged.

The compatibility backfill should be conservative: create missing global assignments from known legacy role values, but do not delete role assignments or attempt to reconcile future institution-specific changes.

`BankCore::Seeds::Rbac.seed!` remains useful for development, test, local rebuilds, and idempotent repair. Call RBAC seeds from `db/seeds.rb`, but do not rely on seeds as the production deploy contract.

Development and test seeds should still create the existing sample operators. RBAC backfill must run after those operators exist.

Existing response contracts should remain stable during the migration. Teller JSON responses may keep legacy messages such as `{ "error": "forbidden", "message": "supervisor role required" }`, and Branch controllers may keep current redirect/flash wording while their underlying checks move to capabilities. Capability-neutral wording can be handled later as a separate UI/API cleanup.

---

## 7. Initial capability set

Seed the capabilities needed for existing workflows and near-term migrations first.

Capability codes follow the pattern `<object>.<action>`. Use the same business object vocabulary as operational events, but use present-tense authority verbs instead of past-tense event facts.

Examples:

```text
Operational event: deposit.accepted
Capability:        deposit.accept

Operational event: hold.released
Capability:        hold.release
```

### Transaction and teller capabilities

- `deposit.accept`
- `withdrawal.post`
- `transfer.complete`
- `teller_session.open`
- `teller_session.close`
- `cash_drawer.manage`

### Control and approval capabilities

- `hold.place`
- `fee.waive`
- `hold.release`
- `reversal.create`
- `teller_session_variance.approve`
- `business_date.close`

### Party and account capabilities

- `party.create`
- `account.open`
- `account.maintain`

### Ops, audit, and reporting capabilities

- `ops.batch.process`
- `ops.exception.resolve`
- `ops.reconciliation.perform`
- `operational_event.view`
- `journal_entry.view`
- `audit.export`
- `report.view`

### Admin capabilities

- `user.manage`
- `role.manage`
- `system.configure`

Capabilities from the broader matrix that do not have shipped workflows yet may be added later when the workflow is implemented. Examples include check cashing, bank draft issuance, external transfers, identity overrides, vault access, vault transfers, high-value approvals, account close, account restrictions, and audit export if export remains unimplemented.

---

## 8. Baseline role-to-capability matrix

The initial matrix is conservative and behavior-preserving. `branch_supervisor` is the compatibility target for existing `operators.role = supervisor` records. `csr`, `branch_manager`, and `auditor` are seeded future-facing bundles, but existing operators are not backfilled into them unless development or test seed data explicitly creates those users.

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

`operations` receives `business_date.close` and `teller_session_variance.approve` to preserve the shipped Ops control surfaces while Teller JSON remains supervisor-equivalent for those same actions.

`system_admin` is a technology administration role, not a financial approval role. Support visibility through `operational_event.view` and `report.view` does not imply authority to waive fees, release holds, create reversals, close the business date, or approve teller-session variances.

---

## 9. Migration order

Migrate one gate group at a time.

### Step 1: Add data and resolver foundation

- Add migrations, models, registry, seeds, and resolver.
- Create baseline RBAC data in migration.
- Backfill role assignments from existing operators in migration.
- Keep all current role checks in place.
- Add safety tests.

Exit criteria:

- Existing tests still pass.
- Existing operators have equivalent RBAC assignments.
- Production deploys do not depend on seeds to preserve existing authorization behavior.
- No production code path depends on RBAC yet.

### Step 2: Reversal approval

Replace supervisor-only reversal checks with:

```ruby
current_operator.has_capability?("reversal.create")
```

Targets:

- Teller reversal create
- Branch reversal create

Regression expectations:

- teller cannot create reversal
- branch supervisor can create reversal
- system admin cannot create reversal by default

### Step 3: Standard approval

Replace selected supervisor approval gates with:

```ruby
current_operator.has_capability?("teller_session_variance.approve")
current_operator.has_capability?("business_date.close")
```

Initial targets:

- teller session variance approval
- business date close, if it remains supervisor-equivalent for the first migration

Do not move no-self-approval, thresholds, or EOD readiness into RBAC.

### Step 4: Fee and hold overrides

Replace fee and hold supervisor gates with:

```ruby
current_operator.has_capability?("fee.waive")
current_operator.has_capability?("hold.release")
```

Initial targets:

- Branch fee waiver
- Branch account hold release

### Step 5: Account maintenance

Replace authorized-signer maintenance supervisor gates with:

```ruby
current_operator.has_capability?("account.maintain")
```

Initial targets:

- authorized signer add
- authorized signer end

If account maintenance becomes too broad, split it later into more specific capability codes such as `account.party.maintain`.

These checks must be enforced inside the Accounts commands, not only in Branch controllers, because the commands are the durable write boundary for authorized-signer maintenance.

### Step 6: Workspace navigation

Only after control-sensitive gates are stable, migrate workspace navigation checks:

- Branch workspace access
- Ops workspace access
- Admin workspace access

Do not make workspace navigation the first migration target. It is broad and easier to over-grant.

---

## 10. Tests

Add focused tests before replacing any role gate.

Foundation tests:

- seeded capability codes are unique
- seeded role codes are unique
- every role-capability link points to a registered capability
- every capability literal used by migrated authorization code exists in `CapabilityRegistry`
- no migrated code references deprecated capability names
- backfill creates expected assignments from existing `operators.role`
- inactive role assignment grants no capabilities
- expired role assignment grants no capabilities
- inactive role grants no capabilities
- inactive capability grants no capabilities
- unknown capability checks fail closed
- `system_admin` does not receive financial approval capabilities by default

Migration tests:

- teller cannot approve reversals
- branch supervisor can approve reversals
- system admin cannot approve reversals by default
- teller cannot approve session variance
- branch supervisor can approve session variance
- branch fee waiver requires `fee.waive`
- branch hold release requires `hold.release`
- authorized-signer maintenance requires `account.maintain`
- privileged command tests prove command-level enforcement even when called without a controller preflight check

Regression stance:

- Each migrated gate must prove the same allow/deny behavior as the old role check unless the change is explicitly called out in the test name and implementation notes.

---

## 11. Deferred work

Defer until after the first RBAC foundation is stable:

- role-management UI
- audit records for role assignment changes
- operating-unit scoped assignments
- branch/location authority resolution
- capability-driven menus and workspace navigation polish
- break-glass financial authority for system administrators
- customer, partner, fintech, ACH participant, wire, card, or external API authorization
- threshold engines, approval queues, or generalized Workflow tables

Before role-management UI ships, role and capability assignment changes must have audit evidence. At minimum, record actor, changed operator, old assignment, new assignment, timestamp, and reason.

Future admin-managed RBAC audit records should capture actor, target operator, role, affected assignment, action, old and new active state, old and new `starts_at` / `ends_at`, reason, and timestamp. Phase 1 may defer the audit table while RBAC changes remain migration/seed-managed.

---

## 12. Implementation plan and checklist

### Implementation plan

Implement RBAC as small vertical slices.

#### Slice 1A: Foundation only

Scope:

- migrations for RBAC tables, indexes, baseline data, and compatibility backfill
- `Workspace::Models::*` RBAC models and associations
- `Workspace::Authorization::CapabilityRegistry` as the code-reviewed source for baseline capability and role-bundle data
- `Workspace::Authorization::CapabilityResolver`
- `Operator#capabilities` and `Operator#has_capability?`
- `BankCore::Seeds::Rbac.seed!` for development, test, local rebuilds, and repair
- foundation, temporal-window, scope, backfill, matrix, and drift tests

Do not replace any production role checks in Slice 1A. The exit condition is that RBAC data exists, resolver behavior is proven, existing operators have equivalent assignments, and no shipped code path depends on RBAC yet.

#### Slice 1B: Reversal creation

Replace reversal authorization with `reversal.create` in the Teller and Branch entry points, with command-level enforcement where the reversal write is performed. Preserve existing JSON and redirect response contracts.

#### Slice 1C: Standard approvals

Replace teller-session variance approval with `teller_session_variance.approve` and business-date close with `business_date.close`, keeping EOD readiness, no-self-approval, variance threshold, and business-date rules outside RBAC.

#### Slice 1D: Fee and hold controls

Replace fee waiver and hold release gates with `fee.waive` and `hold.release`. Keep hold eligibility, linked-deposit constraints, and posting/reversal guards in the owning domain commands.

#### Slice 1E: Account maintenance

Replace authorized-signer maintenance supervisor checks with `account.maintain` inside the Accounts commands. Keep account status, party validity, idempotency replay, and audit writes in Accounts.

#### Slice 1F: Workspace navigation

Only after control-sensitive writes are stable, migrate Branch, Ops, and Admin navigation helpers to capability checks. This should be a UI/navigation cleanup, not a control replacement for privileged writes.

### Ordered checklist

1. Add RBAC migrations.
2. Add RBAC models and associations.
3. Add `CapabilityRegistry`.
4. Add `CapabilityResolver`.
5. Add `Operator#capabilities` and `Operator#has_capability?`.
6. Create baseline RBAC data and compatibility assignments in migration.
7. Add `BankCore::Seeds::Rbac.seed!`.
8. Call RBAC seeds from `db/seeds.rb`.
9. Add foundation tests and capability drift tests.
10. Stop after the foundation slice and verify no production code path depends on RBAC yet.
11. Migrate reversal approval checks.
12. Add reversal authorization regression tests.
13. Migrate standard approval checks.
14. Add standard approval regression tests.
15. Migrate fee and hold override checks.
16. Add override regression tests.
17. Migrate account maintenance checks.
18. Add account maintenance regression tests.
19. Revisit workspace navigation checks after control gates are stable.

---

## 13. Success criteria

RBAC Phase 1 is complete when:

- baseline capabilities and role bundles are registry-managed and created by migration
- existing operators are backfilled into equivalent role assignments
- high-control supervisor gates are capability-based
- existing behavior is preserved by tests
- system administrators do not accidentally gain financial approval authority
- `operators.role` remains available for compatibility
- no financial posting, ledger, business-date, or reversal invariant changes are introduced
