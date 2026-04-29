# ADR-0032: Operating units and branch scope

**Status:** Accepted - first slice implemented  
**Date:** 2026-04-27  
**Decision Type:** Workspace / branch operating model architecture  
**Aligns with:** [ADR-0018](0018-business-date-close-and-posting-invariant.md), [ADR-0025](0025-internal-workspace-ui.md), [ADR-0026](0026-branch-csr-servicing.md), [ADR-0029](0029-capability-first-authorization-layer.md), [ADR-0031](0031-cash-inventory-and-management.md), [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Context and Problem Statement

BankCORE currently uses `branch` in two different ways:

- as an internal Rails HTML workspace namespace for teller-adjacent and CSR servicing screens
- as a business concept in planning language, for example "Can we run a branch safely?"

The application does not yet model branches, departments, regions, vault locations, or operating units as first-class records. That was acceptable while BankCORE had one conceptual branch and global staff roles, but several accepted and proposed ADRs now need a shared scope primitive:

- ADR-0029 prepares capability assignments for future branch, location, or operating-unit scope.
- ADR-0031 needs branch or operating-unit references for cash locations.
- Teller sessions and cash drawer controls need to know where cash work happened.
- Branch CSR servicing needs audit clarity beyond the HTTP workspace namespace.
- Future reporting, EOD readiness, cash reconciliation, and audit review need to group activity by organizational place.

BankCORE needs a model for operating units before it adds scoped authorization, branch cash custody, branch dashboards, or branch-aware audit reporting. That model must not accidentally introduce multi-branch business dates, branch-level GL ledgers, or multi-entity accounting before those concerns are explicitly designed.

---

## 2. Decision Drivers

- Provide one canonical organizational scope model for staff, teller, cash, audit, and reporting use.
- Preserve the current singleton business date and centralized financial kernel.
- Avoid encoding branch behavior into workspace route names, role strings, or cash-location enums.
- Support future branches, departments, regions, and centralized operations without redesigning scoped authorization.
- Make branch/location context durable audit data for operator actions.
- Keep the first implementation slice small enough to support current branch-safe MVP work.
- Avoid treating operating-unit scope as a ledger segment, legal entity, or separate books model.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **Keep branch as a UI namespace only** | No new persistence; matches the current Branch workspace. | Cannot scope authorization, cash locations, teller sessions, audit evidence, or reporting. |
| **Add a `branches` table only** | Simple and intuitive for teller/cash workflows. | Too narrow for operations centers, regions, departments, centralized vaults, or future non-branch scopes. |
| **Add a general `operating_units` model with branch as the first unit type** | Creates one reusable scope primitive for branch, cash, staff authority, audit, and reporting. | Requires clearer rules so teams do not treat it as multi-entity accounting or branch-level business date behavior. |
| **Use GL segments or entities as branch scope** | Aligns with future financial reporting dimensions. | Prematurely couples operational scope to accounting structure and risks fragmenting the ledger model. |

---

## 4. Decision Outcome

**Chosen Option: Add a general `operating_units` model with branch as the first unit type.**

BankCORE will introduce operating units as the canonical organizational scope for internal operations. A branch is an operating unit with `unit_type: branch`.

Operating units answer:

```text
Where is this internal work happening?
Which organizational unit owns or supervises this operational resource?
What scope applies to this staff authority assignment?
```

Operating units do not answer:

```text
Which ledger owns this money?
Which business date is open?
Which legal entity owns these books?
```

The first implementation should seed one institution-level operating unit and one branch-level operating unit so existing single-branch behavior can become explicit without changing financial outcomes.

### 4.1 Core invariants

- Operating-unit scope is operational and organizational; it is not a second ledger.
- Posting, journal entries, journal lines, trial balance, and account balances remain owned by the existing financial kernel.
- Business date remains the singleton model from ADR-0018 unless a future ADR introduces branch-scoped business dates.
- Branch workspace routes do not imply branch scope by themselves; controllers must resolve scope from authenticated operator/session context or explicit persisted records.
- Staff authority may be global or operating-unit scoped, but capabilities remain attempt authorization only. Conditional controls stay in policy, command, workflow, and domain validation layers.
- Corrections to scope-sensitive operational records must be auditable. Posted financial history must not be silently rewritten to change operating-unit attribution.

---

## 5. Domain Ownership

### 5.1 `Organization`

`Organization` owns the operating-unit reference model and hierarchy.

It should own:

- `operating_units`
- operating-unit status and hierarchy validation
- operating-unit lookup and tree queries
- default seeded institution and branch records

Representative services:

- `Organization::Models::OperatingUnit`
- `Organization::Queries::OperatingUnitTree`
- `Organization::Services::DefaultOperatingUnit`

`Workspace` continues to own staff identity, operator defaults, authorization context, and RBAC persistence. It consumes `Organization` operating units for scoped authorization but does not own the organizational reference data.

It should own:

- operator home or default operating-unit references
- scoped operator role assignments from ADR-0029
- current internal authorization context resolution
- `Workspace::Authorization::CapabilityResolver`

### 5.2 `Teller`

`Teller` owns teller-session lifecycle and should record the operating unit where a session is opened.

Teller sessions should eventually include:

```text
operating_unit_id
cash_location_id
operator_id
business_date
status
```

Teller commands must reject ambiguous scope once the first implementation requires operating-unit context for teller sessions.

### 5.3 `Cash`

`Cash` owns cash locations and custody movement. Cash locations should reference operating units once ADR-0031 is implemented.

Examples:

```text
Main Branch Vault -> operating_unit: Main Branch
Teller Drawer 3   -> operating_unit: Main Branch
Central Vault     -> operating_unit: Central Operations
```

Cash commands must keep custody scope separate from GL ownership. Internal movement between two cash locations may change operating-unit custody without changing aggregate GL cash when both locations remain within institutional custody.

### 5.4 Core domains

`Core::OperationalEvents` should preserve actor, channel, business date, and operating-unit context for staff-originated internal events where scope can be resolved.

`Core::Posting`, `Core::Ledger`, and `Core::BusinessDate` remain centralized in this ADR. They must not infer branch-level books or branch-level business dates from operating-unit records.

---

## 6. Data Model

### 6.1 `operating_units`

Stores the organizational units used for internal staff scope, branch operations, cash custody, and reporting.

```text
id
code
name
unit_type
parent_operating_unit_id
status
time_zone
opened_on
closed_on
created_at
updated_at
```

Initial `unit_type` values:

```text
institution
branch
operations
department
region
```

Initial `status` values:

```text
active
inactive
closed
```

Rules:

- `code` is unique and stable enough for operator-facing configuration and seeded references.
- `unit_type` is an operating model classification, not an authorization role.
- `parent_operating_unit_id` supports a simple hierarchy such as institution -> region -> branch.
- `parent_operating_unit_id` must not reference the same operating unit.
- `time_zone` is operational metadata and does not create a separate business date.
- `closed_on` prevents new routine assignment or location creation after closure, but historical records remain linked.
- first-slice scoped authorization is exact-match only; region, department, or parent-unit inheritance requires a future ADR.

### 6.2 Operator references

The first implementation may add a default operating-unit reference to operators:

```text
operators.default_operating_unit_id
```

This is a convenience for current UI/session scope. It is not the full authority model. Actual authority should come from ADR-0029 role assignments once that layer is implemented.

### 6.3 Scoped role assignments

ADR-0029's scope fields should use operating units as the first concrete scope type:

```text
operator_role_assignments.scope_type = "operating_unit"
operator_role_assignments.scope_id = operating_units.id
```

Global assignments remain represented by `scope_type: nil` and `scope_id: nil`.

### 6.4 Operational records

First-slice records that should carry operating-unit context:

- `teller_sessions.operating_unit_id`
- `operational_events.operating_unit_id` for staff-originated internal events where scope can be resolved
- `cash_locations.operating_unit_id` once Cash is implemented
- `cash_movements` via source and destination cash locations

Future records that may carry operating-unit context directly:

- approval requests and approval decisions
- reporting extracts or materialized branch dashboards

The implementation should avoid duplicating operating-unit id on every table until there is a concrete query, audit, or integrity need. Derivation through teller session, cash location, operator assignment, or operational event may be sufficient for early slices.

---

## 7. Scope Resolution

Internal requests should resolve operating-unit context explicitly.

Initial resolution order for Branch HTML teller-adjacent workflows:

1. Use the open teller session's `operating_unit_id` when the action depends on teller session state.
2. Use the selected cash location's `operating_unit_id` for cash location workflows.
3. Use the authenticated operator's default operating unit for read-only branch navigation and form defaults.
4. Require an explicit operator-selected operating unit when an operator has authority in multiple active units and no session or location determines the scope.

Controllers must not trust a hidden field or arbitrary param as proof of scope authority. If a form submits `operating_unit_id`, the controller or command must verify that the authenticated operator may act in that unit through the scoped authorization resolver or a temporary compatibility rule.

---

## 8. Worked Examples

### 8.1 Teller opens a session at Main Branch

Command:

```text
Teller::Commands::OpenSession
  operator_id: 101
  operating_unit_id: main_branch
  business_date: current open day
  opening_cash_minor_units: 100000
```

Operational result:

- Create an open teller session linked to Main Branch.
- Use the session operating unit for teller cash transactions during that session.
- Keep transaction posting behavior unchanged.

Posting outline:

```text
No journal entry for opening the session.
Future deposits and withdrawals post through existing operational events and posting rules.
```

### 8.2 Branch supervisor authority is scoped to one branch

Assignment:

```text
Operator 202
  role: branch_supervisor
  scope_type: operating_unit
  scope_id: main_branch
```

Behavior:

- The operator may approve branch-supervisor actions in Main Branch.
- The same operator has no supervisor authority in another branch unless granted globally or assigned there too.
- No-self-approval, thresholds, active session, and business-date checks still run outside capability resolution.

### 8.3 Vault-to-drawer cash movement

Command:

```text
Cash::Commands::TransferCash
  source_location: Main Branch Vault
  destination_location: Teller Drawer 3
  amount_minor_units: 100000
  currency: USD
  actor_id: 101
  approval_actor_id: 202
```

Operational result:

- Both locations carry `operating_unit_id: main_branch`.
- Cash custody moves from vault to drawer.
- No GL posting occurs for an internal custody transfer within institutional cash.

Posting outline:

```text
No journal entry.
Cash subledger:
  Main Branch Vault -100000
  Teller Drawer 3   +100000
```

---

## 9. MVP Boundary and Phasing

### First operating-unit slice

The first implementation slice is implemented with:

- `operating_units` with seeded institution and branch records
- `operators.default_operating_unit_id` or equivalent session-default support
- `teller_sessions.operating_unit_id`
- `operational_events.operating_unit_id` for staff-originated internal events where scope can be resolved
- operating-unit scope object support for ADR-0029 capability resolution
- Branch UI/session defaults that make the current branch explicit
- tests proving existing single-branch teller and Branch CSR behavior remains unchanged

Implementation caveat: branch/cash workflows must continue to authorize against the resolved operating unit that owns the session, cash location, movement, or variance. Global role assignments remain valid, but operating-unit-scoped assignments are exact-match only.

### Follow-up slices

Likely follow-up work:

- broader scoped role assignment backfill and administration screens
- branch-aware operational event search filters
- branch cash position and reconciliation reports
- branch dashboards for open sessions, pending approvals, and cash exceptions

### Deferred

The following are post-MVP unless a selected branch story requires them earlier:

- branch-scoped business dates
- day close by branch or region
- branch GL segments or branch-level financial statements
- multi-entity accounting
- interbranch settlement accounting
- customer/account home-branch ownership rules
- branch transfer, consolidation, merger, and closure workflows
- branch holiday calendars and cutoff policies

---

## 10. Technical Consequences

Positive:

- Gives BankCORE one reusable scope primitive for staff authority, teller sessions, cash custody, audit, and reporting.
- Lets ADR-0029 scoped authorization become concrete without inventing branch-specific role logic.
- Supports ADR-0031 cash locations without overloading cash-location type values.
- Improves audit evidence for where internal staff work happened.

Negative:

- Adds organizational reference data and scope-resolution code.
- Requires migration and seed discipline even in the current single-branch implementation.
- Creates risk that teams accidentally infer financial segmentation from operational scope.
- Requires authorization tests for multi-unit staff scenarios once scoped roles are enforced.

Neutral:

- Existing Branch HTML routes remain the same.
- Existing teller JSON routes can preserve current behavior while defaulting to the seeded branch during migration.
- Operating-unit hierarchy can remain shallow until regional or centralized operations workflows need it.

---

## 11. Risks and Mitigations

| Risk | Mitigation |
| :--- | :--- |
| Operating units become a second ledger segmentation model | State explicitly that ledger and posting remain centralized; require a future GL ADR for branch financial statements or segment accounting. |
| Branch routes are mistaken for branch authority | Resolve scope from session, cash location, operator context, or explicit authorized selection, not route namespace alone. |
| Default branch masks missing scope in multi-branch scenarios | Allow defaulting only while the system has one seeded branch or for read-only navigation; require explicit scope once multiple units are active. |
| Scoped authorization bypasses conditional controls | Keep capabilities as attempt authorization only; enforce thresholds, no-self-approval, dual control, business date, and session rules in commands and workflow. |
| Historical records lose branch context after organizational changes | Keep operating-unit rows stable and historical links intact; close or inactivate units rather than deleting them. |
| Operating-unit hierarchy gets over-modeled | Start with institution and branch; add region, department, and operations usage only when a workflow needs them. |

---

## 12. Open Questions

1. Should parent operating-unit authorization inheritance be introduced for region and department scopes, or should all scoped authorization remain exact-match until an explicit workflow needs inherited authority?
2. How should operating-unit reassignment of active operators be audited once Admin role and operator management screens ship?
3. Should account opening record an account home operating unit, or should customer/account home-branch ownership remain deferred?
4. What compatibility behavior should teller JSON APIs use before clients send explicit operating-unit context?
5. Should inactive and closed operating units remain selectable for historical reporting but blocked for new sessions, locations, and role assignments?
6. Should branch-aware EOD readiness be a filtered view over the singleton business date, or should it wait until branch-scoped business dates are designed?

---

## 13. Decision Summary

BankCORE will model branches as operating units rather than treating branch as only a UI namespace or a special-purpose teller/cash field.

Operating units provide durable organizational scope for staff authority, teller sessions, cash locations, audit evidence, and branch reporting. They do not create branch-level business dates, branch ledgers, or separate financial truth. The first slice should seed one institution and one branch, attach teller sessions and staff defaults to that scope, and prepare scoped authorization while preserving the current singleton business date and centralized posting/ledger model.
