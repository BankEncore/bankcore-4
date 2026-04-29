# BankCORE branch operations roadmap

**Status:** Draft  
**Last reviewed:** 2026-04-29  

This roadmap sequences branch-operations work for BankCORE. It does **not** redefine scope: MVP boundaries stay in [docs/concepts/01-mvp-vs-core.md](concepts/01-mvp-vs-core.md), ownership stays in [docs/architecture/bankcore-module-catalog.md](architecture/bankcore-module-catalog.md), and durable design decisions stay in the ADRs under [docs/adr/](adr/).

Use this document to choose vertical slices. When a slice changes posting rules, reversal semantics, GL ownership, branch business-date behavior, product behavior, or external integration contracts, add or update an ADR before implementation.

---

## 1. Purpose

BankCORE's branch goal is not "build every branch feature." The near-term goal is:

```text
Can we run a branch safely?
```

That means the branch can create customers and accounts, perform controlled teller transactions, prove balanced books, reconcile teller work, preserve audit evidence, and close the day without silent edits or balance drift.

This roadmap keeps that goal separate from broader full-core capabilities such as full product engines, external payment origination, branch GL segments, full compliance case management, and multi-entity accounting.

---

## 2. Boundary Rules

1. **Branch is a workspace/channel, not a financial kernel.** Branch and Teller controllers orchestrate domain commands; they do not own posting, ledger, or balance truth.
2. **Operating units provide operational attribution and authorization scope.** They do not imply separate ledgers, branch business dates, or automatic GL segmentation.
3. **Teller sessions control operator drawer activity.** They are not the institutional cash inventory system.
4. **Cash locations control physical custody.** Cash movements, counts, and custody balances belong in `Cash`; only GL-impacting exceptions or external cash events require posting.
5. **Operational events record durable business facts.** Eligible financial events post through `Core::Posting` into journal entries and journal lines.
6. **Product rules determine allowed/default behavior.** Posting rules determine accounting treatment.
7. **Servicing workflows may create audit records without journal entries.** Not every operational control is a GL event.
8. **Corrections are explicit forward actions.** Use reversals, voids, replacements, releases, expirations, or superseding rows; do not mutate posted history.

---

## 3. Module Ownership


| Area                                                                        | Primary owner                          |
| --------------------------------------------------------------------------- | -------------------------------------- |
| Customer records and identity                                               | `Party`                                |
| Deposit account contract/state, account parties, holds, restrictions        | `Accounts`                             |
| Product configuration and behavior templates                                | `Products`                             |
| Deposit servicing behavior: interest, fees, statements, overdraft, maturity | `Deposits`                             |
| Teller sessions and workstation flows                                       | `Teller`                               |
| Cash locations, custody movement, counts, balances, variances               | `Cash`                                 |
| Staff identity, capabilities, role assignments                              | `Workspace`                            |
| Branch/department/operations scope                                          | `Organization`                         |
| Approval requests and maker-checker workflows                               | `Workflow`                             |
| Operational intent and audit facts                                          | `Core::OperationalEvents`              |
| Event-to-journal conversion                                                 | `Core::Posting`                        |
| Journal and GL truth                                                        | `Core::Ledger`                         |
| Business-date governance and close orchestration                            | `Core::BusinessDate`                   |
| External rail adapters and ingestion/origination                            | `Integration`                          |
| Evidence, reports, extracts, and oversight                                  | `Documents`, `Reporting`, `Compliance` |


---

## 4. Phase 0: Canonical Capability Map

**Goal:** create a shared map from branch activities to module ownership, operational events, posting behavior, read models, and audit controls.

### Scope

- Classify each branch activity as `MVP`, `near-term`, or `post-MVP`.
- Name the owning module and command/query surface for each activity.
- Identify whether the activity creates:
  - an operational event
  - a posting
  - an audit row
  - a read model
  - reference data only
- Link each activity to existing ADR coverage or mark the ADR gap.

### Output

Recommended artifact:

```text
docs/architecture/branch-operations-capability-map.md
```

See [branch operations capability map](architecture/branch-operations-capability-map.md).

This is a planning/catalog pass only. It must not introduce new money movement semantics by itself.

---

## 5. Phase 1: Branch-Safe Transaction MVP

**Goal:** a branch can open accounts, move money safely, balance teller work, and prove the books.

### Current / Shipped Foundation — Confirmed

Phase 1 is implemented on this branch. The shipped foundation includes:

- Party and basic deposit account creation through Teller and Branch workflows.
- Deposit account product FK and cached product code.
- Teller and Branch cash deposit, withdrawal, and transfer flows.
- Operational events for core money movements.
- Posting through `Core::Posting` into balanced journal entries.
- Holds and available-balance checks.
- Fee assessment and fee waiver paths.
- Reversals as explicit compensating events.
- Teller sessions, close, variance, and supervisor/capability approval.
- Trial balance and EOD readiness reads.
- Staff operators, capability-based authorization, and operating-unit scope.

Implementation evidence:

- Party/account creation and Branch transaction forms: `[test/integration/branch_transaction_forms_test.rb](../test/integration/branch_transaction_forms_test.rb)`.
- Teller session cash policy and operating-unit attribution: `[test/integration/teller/teller_session_cash_policy_test.rb](../test/integration/teller/teller_session_cash_policy_test.rb)`.
- RBAC tables and role/capability backfill: `[db/migrate/20260424120016_create_rbac_tables.rb](../db/migrate/20260424120016_create_rbac_tables.rb)` and `[test/domains/workspace/capability_resolver_test.rb](../test/domains/workspace/capability_resolver_test.rb)`.
- Operating-unit reference model and scope references: `[db/migrate/20260424120017_create_operating_units_and_scope_refs.rb](../db/migrate/20260424120017_create_operating_units_and_scope_refs.rb)` and `[test/domains/organization/operating_unit_test.rb](../test/domains/organization/operating_unit_test.rb)`.
- Branch servicing holds, fee waivers, and reversals: `[test/integration/branch_customer_servicing_test.rb](../test/integration/branch_customer_servicing_test.rb)`.

Phase 1 has teller-session cash control only. Institutional vault/drawer custody, branch cash positions, and cash-location reconciliation remain Phase 2.

### Owners

- `Party`: customer records.
- `Accounts`: deposit accounts, account parties, holds, available-balance support.
- `Teller`: teller sessions and workstation workflows.
- `Core::OperationalEvents`: durable event facts and idempotency.
- `Core::Posting` / `Core::Ledger`: financial truth.
- `Workspace` / `Organization`: actor and branch scope.

### Completion Criteria

- Deposits, withdrawals, transfers, fees, holds, and reversals post or record through the approved paths.
- Cash-affecting teller transactions require open teller-session context where configured.
- Posted journals are balanced and immutable.
- Operational events preserve actor, channel, business date, teller session where applicable, and operating-unit context where resolved.
- EOD readiness can identify unresolved sessions, pending events, and trial-balance issues.

### Deferred

- Full cash location inventory.
- Branch-scoped business dates.
- Branch GL segments.
- Account lifecycle restrictions beyond shipped servicing slices.
- Full product behavior engine.

---

## 6. Phase 2: Cash Custody and Branch Controls

**Goal:** move from teller-session cash control to true branch cash custody.

Phase 2 is the first implementation slice of [ADR-0031](adr/0031-cash-inventory-and-management.md), using operating-unit scope from [ADR-0032](adr/0032-operating-units-and-branch-scope.md) and capability gates from [ADR-0029](adr/0029-capability-first-authorization-layer.md). It should be implemented as reviewable sub-phases rather than one broad cash rewrite.

### Owners and Boundaries

- `Cash`: locations, movements, counts, custody balances, reconciliation.
- `Teller`: session lifecycle only.
- `Workspace`: cash-operation capabilities.
- `Workflow`: durable approvals when maker-checker is generalized.
- `Core::Posting`: only for GL-impacting variance or external cash events.

### Boundary

```text
Teller session = operator work control
Cash location = institutional custody control
Ledger = financial accounting truth
```

### Phase 2A: Cash Reference Foundation

Add Cash-owned location reference data.

Tables:

- `cash_locations`

Initial fields:

- `operating_unit_id`
- `location_type`
- `code`
- `name`
- `currency`
- `status`
- `responsible_operator_id`
- `parent_cash_location_id`
- `requires_balancing`
- timestamps

Initial location types:

- `branch_vault`
- `teller_drawer`
- `internal_transit`

Initial commands/models:

- `Cash::Models::CashLocation`
- `Cash::Commands::CreateLocation`

Rules:

- `operating_unit_id` must reference an active operating unit.
- `code` must be stable and unique.
- `currency` must be explicit.
- Closed or inactive locations must remain visible for history but blocked for new routine movements.
- Seed/configure one Main Branch vault and one teller drawer only if it matches the current seed style for development/test setup.

### Phase 2B: Teller Drawer Linkage

Connect teller sessions to drawer custody without moving session ownership out of `Teller`.

Table changes:

- Add `teller_sessions.cash_location_id`.

Command changes:

- Update `Teller::Commands::OpenSession` to accept or resolve a drawer `cash_location_id`.
- Preserve current behavior when no drawer location is supplied during migration.

Rules:

- The linked location must be active.
- The linked location must have `location_type: teller_drawer`.
- The linked location must belong to the same operating unit as the session.
- Only one open teller session may use the same drawer location at a time.
- Teller cash deposits and withdrawals still record customer financial activity through `Core::OperationalEvents` and `Core::Posting`; drawer linkage is custody context, not posting logic.

### Phase 2C: Internal Custody Movements

Add append-oriented internal cash movement and rebuildable balance projections.

Tables:

- `cash_movements`
- `cash_balances`

Initial command:

- `Cash::Commands::TransferCash`

Supported first-slice movements:

- branch vault to teller drawer
- teller drawer to branch vault
- branch vault or drawer to internal transit
- internal transit back to a vault or drawer

Movement fields should include:

- source cash location
- destination cash location
- amount in minor units
- currency
- business date
- initiating actor
- approving actor when required
- status
- reason code or movement type
- idempotency key
- related operational event when applicable

Initial movement statuses:

- `pending_approval`
- `approved`
- `completed`
- `cancelled`
- `rejected`

Rules:

- Internal custody movement stays within institutional cash and must not post a journal entry.
- Completed internal movements may record no-GL `cash.movement.completed` operational events.
- Balance projections must update in the same database transaction as completion.
- `cash_balances` are projections only; they must be rebuildable from movement/count history.
- Vault-involved movements require approval according to Cash command policy.
- No-self-approval belongs in Cash/Workflow command logic, not in RBAC capability strings.

### Phase 2D: Counts and Variances

Add physical count evidence and variance tracking.

Tables:

- `cash_counts`
- `cash_variances`

Initial command:

- `Cash::Commands::RecordCashCount`

Rules:

- Counts must record cash location, counted amount, expected amount, currency, business date, actor, and timestamps.
- Counts are append-oriented; do not silently edit prior count history.
- A non-zero difference creates a cash variance record.
- Variances above configured policy require approval.
- Variance approval must enforce no-self-approval outside RBAC.
- `cash.count.recorded` is a no-GL operational event candidate.

Open decision:

- Defer GL variance posting or implement it as a separate explicit follow-up. ADR-0031 still leaves open whether teller-session variance should keep using `teller.drawer.variance.posted` or whether Cash should introduce a broader `cash.variance.posted`.

### Phase 2E: Read Models and EOD Hooks

Add Cash read APIs and EOD readiness composition after command behavior is tested.

Queries:

- `Cash::Queries::CashPosition`
- `Cash::Queries::LocationActivity`
- `Cash::Queries::ReconciliationSummary`
- `Cash::Queries::PendingCashApprovals`

Read surfaces:

- Branch workspace cash position and location activity.
- Ops workspace exception/reconciliation views if the slice needs oversight beyond Branch.

EOD readiness hooks:

- unresolved `pending_approval` cash movements
- unresolved cash variances
- stale or missing required counts, once count policy is enabled
- cash projection drift detected by reconciliation queries

EOD policy should start as read-only evidence or warning unless the selected slice explicitly decides that cash exceptions block close.

### Candidate Event Families

- `cash.movement.completed` — no GL for internal transfers within institutional custody.
- `cash.count.recorded` — no GL by default.
- `cash.variance.posted` — optional GL follow-up only after the variance-event decision is made.

Internal vault/drawer movement must stay within GL `1110` and create no journal entry. Any external cash shipment or settlement event requires a separate COA/posting decision before implementation.

### Phase 2 Test Plan

Add focused tests before adding workspace polish:

- Cash location model constraints: valid types, active operating unit, unique code, closed/inactive behavior.
- Teller session drawer linkage: active drawer, same operating unit, one open session per drawer.
- Internal cash transfer command: idempotency, status transitions, no balance movement before approval/completion, no-self-approval, and sufficient source custody balance.
- Cash balance projection: completed movements update projections and can be rebuilt from movement history.
- No-GL proof: internal custody movement records no journal entry.
- Cash count command: creates count evidence and variance records when counted amount differs from expected amount.
- EOD readiness hooks: unresolved movements/variances surface in readiness output once enabled.
- Existing Phase 1 integration tests continue to pass.

### Deferred

- Fed/correspondent cash shipments.
- ATM cash.
- Denomination tracking.
- Strap, bundle, roll, and coin tracking.
- External cash settlement accounting.
- Branch-level GL.
- Branch-scoped business dates.
- External cash settlement accounts or COA changes.
- Generalized `Workflow` tables unless a cash approval slice explicitly requires them.

---

## 7. Phase 3: Branch Servicing Depth

**Goal:** make branch/platform servicing complete enough for daily account maintenance.

### Scope

- Account restrictions, freezes, and status changes.
- Account close and possible reopen policy.
- Post-open account-party servicing beyond the shipped authorized-signer slice.
- Customer profile maintenance.
- Statement/history review.
- Fee waiver, hold release, reversal, and exception review through Branch workspace.
- Durable audit for servicing changes.

### Candidate Events / Audit Records

- `account.restricted`
- `account.unrestricted`
- `account.closed`
- `party.contact.updated`
- account-party maintenance audit rows

Exact event taxonomy should be decided per slice. Some servicing changes may be better represented as domain audit rows rather than GL or financial operational events.

### Owners

- `Accounts`: account state, relationships, restrictions, lifecycle.
- `Party`: customer identity and contact data.
- `Branch` controllers: workspace orchestration only.
- `Workflow`: approvals once maker-checker is generalized.

### Deferred

- Full KYC/CIP automation.
- Document retention workflows.
- Customer self-service.
- Contact-center-specific `CustomerService` workspace, unless a separate operating model emerges.

---

## 8. Phase 4: Product Behavior Engine

**Goal:** make deposit-account behavior reproducible from product configuration rather than hardcoded command logic.

### Scope

- Account-level product contract snapshots.
- Deposit product behavior resolver.
- Product-driven limits, fees, holds, overdraft, interest, statement behavior, and lifecycle defaults.
- Rule trace/audit linkage to operational events, holds, approvals, or servicing records.

### Fee Split


| Fee capability                  | Phase             |
| ------------------------------- | ----------------- |
| Simple/manual fee posting       | Phase 1           |
| Fee waiver with audit           | Phase 1 / Phase 3 |
| Product-configured fee rules    | Phase 4           |
| Automated fee assessment cycles | Phase 4+          |


### Owners

- `Products`: product configuration.
- `Deposits`: product-driven servicing decisions.
- `Accounts`: account state.
- `Core::`*: posting, ledger, and business-date invariants remain unchanged.

### Deferred

- Per-product GL mapping until a dedicated posting/GL slice.
- Full CD/time-deposit lifecycle unless selected as a vertical slice.
- Full Reg CC collected-funds engine.

---

## 9. Phase 5: Negotiable Instruments / Official Checks

**Goal:** support check cashing and official checks without overloading Teller or Accounts.

### Recommended First Slice

Start with account-funded official check issuance.

Candidate event:

```text
official_check.issued
```

Likely posting:

```text
Dr 2110 customer DDA
Cr 2160 Official Checks Outstanding
```

### Ownership Decision Needed

This phase requires an ADR before implementation. The ADR should decide whether the owning domain is:

- `Instruments` as a top-level domain for official checks, drafts, and lifecycle records; or
- another explicitly named domain if the first slice is tightly coupled to external payment rails.

`Teller` should initiate the workflow, but it should not own the instrument lifecycle. `Core::Posting` should own posting rules. `Cash` is involved only for cash-funded issuance or cash payout.

### Later Slices

- Cash-funded official checks.
- On-us check cashing.
- Transit check cashing.
- Void, stop, paid, returned, replacement lifecycle.
- Reconciliation and positive pay.

### Deferred

- Full check clearing network integration.
- Full official check reconciliation.
- Positive pay.
- Mobile/ATM check deposit.

---

## 10. Phase 6: External Payments, Rails, and Exceptions

**Goal:** connect external movement to BankCORE while preserving the same operational event and posting kernel.

### Inbound Ingestion Track

- ACH receipt files.
- Card/ATM settlement files.
- Returned items.
- Exception handling.
- File/batch lifecycle tracking.

### Outbound Origination Track

- ACH origination.
- Wires.
- Official-check disbursement files, if applicable.
- External disbursement and settlement workflows.

### Owners

- `Integration`: rail adapters and ingestion/origination contracts.
- `Core::OperationalEvents`: canonical event facts.
- `Core::Posting`: settlement/accounting effects.
- `Accounts`: account validation and available funds.
- `Ops` controllers: internal upload/review workspace when applicable.

### Deferred

- Real-time rail scale concerns.
- Full NACHA parsing beyond accepted slices.
- Disputes and provisional credit unless separately scoped.
- External channel identity/authorization outside accepted API ADRs.

---

## 11. Phase 7: Compliance, Reporting, and Scale

**Goal:** production-grade oversight, evidence, reporting, and regulatory operations.

### Scope

- AML/CTR/sanctions workflows.
- Compliance cases and evidence.
- Operational dashboards.
- Reporting snapshots and extracts.
- Branch-aware event filters and support tools.
- Multi-branch and eventually multi-entity accounting decisions.

### Owners

- `Compliance`: cases, alerts, review evidence.
- `Reporting`: read projections, extracts, snapshots.
- `Documents`: retained artifacts.
- `Core::Ledger`: financial reporting truth.
- `Organization`: operating-unit scope and hierarchy metadata.

### Deferred Until Explicit ADR

- Branch-scoped business dates.
- Branch GL segments.
- Multi-entity consolidation.
- Interbranch settlement.
- Region/department inherited authorization.

---

## 12. MVP Boundary

The branch-safe MVP should prove:

- Customers and accounts can be created.
- Deposits, withdrawals, transfers, fees, holds, and reversals are controlled and auditable.
- Teller sessions and operating-unit scope are durable context.
- Journals balance and posted history is immutable.
- Trial balance proves the books.
- EOD readiness exposes unresolved work.
- Cash drawer control exists, even if full vault/cash inventory comes next.

Everything beyond that should be pulled forward only when it strengthens financial correctness, auditability, or the selected branch operating story.

---

## 13. ADR Triggers

Create or update an ADR before implementing any slice that:

- adds a new GL-backed `event_type`
- changes reversal, void, return, replacement, or correction semantics
- changes posting rules or GL account ownership
- adds branch-scoped business dates or branch GL segmentation
- introduces cash location balances or external cash settlement
- introduces negotiable-instrument lifecycle records
- changes product behavior source of truth
- adds external payment origination or a new rail contract
- adds durable approval/workflow tables

---

## 14. References

- [MVP vs Full System](concepts/01-mvp-vs-core.md)
- [BankCORE module catalog](architecture/bankcore-module-catalog.md)
- [Main development roadmap](roadmap.md)
- [Deferred roadmap completion guide](roadmap-deferred-completion.md)
- [ADR-0029: Capability-first authorization layer](adr/0029-capability-first-authorization-layer.md)
- [ADR-0030: Deposit account product engine](adr/0030-deposit-account-product-engine.md)
- [ADR-0031: Cash inventory and management](adr/0031-cash-inventory-and-management.md)
- [ADR-0032: Operating units and branch scope](adr/0032-operating-units-and-branch-scope.md)

