# ADR-0031: Cash inventory and management

**Status:** Proposed  
**Date:** 2026-04-27  
**Decision Type:** Cash domain / operational control architecture  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0003](0003-posting-journal-architecture.md), [ADR-0010](0010-ledger-persistence-and-seeded-coa.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0014](0014-teller-sessions-and-control-events.md), [ADR-0018](0018-business-date-close-and-posting-invariant.md), [ADR-0020](0020-teller-drawer-variance-gl-posting.md), [ADR-0029](0029-capability-first-authorization-layer.md), [ADR-0037](0037-internal-staff-authorized-surfaces.md), [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Context and Problem Statement

BankCORE currently supports teller cash activity through financial operational events, GL posting, and teller sessions. This is enough for the early branch-safe teller slice, but it does not yet model institutional cash custody as a first-class operational domain.

Cash needs controls that the General Ledger does not provide by itself:

- where physical cash is held
- who is responsible for it
- how cash moved between vaults, drawers, and other custody locations
- which counts confirmed or challenged custody balances
- which variances require review, approval, or GL adjustment
- how operational cash positions reconcile to GL cash balances

The GL remains the financial reporting truth. It must not become the operational location system. Conversely, a cash location model must not become a second financial ledger.

The module catalog already reserves `Cash` for cash locations, vault transfers, counts, adjustments, reconciliation artifacts, and cash position queries. This ADR defines the target model and a narrow first slice that fits BankCORE's current MVP posture: "Can we run a branch safely?"

---

## 2. Decision Drivers

- Preserve the single financial write path: material financial effects flow through `Core::OperationalEvents` and `Core::Posting`.
- Keep custody/location tracking separate from GL reporting.
- Make cash movement and count history immutable or append-oriented.
- Support teller session balancing without forcing all cash control into `Teller`.
- Enable branch vault, teller drawer, ATM, and external shipment growth without redesigning the core model.
- Keep MVP focused on branch vault and teller drawer control.
- Avoid silently changing the meaning of existing GL accounts, especially seeded COA account `1120`, which currently represents ACH settlement.
- Require business-date attribution, actor attribution, and approval evidence for control-sensitive cash operations.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **Use GL only** | Smallest implementation; trial balance already exists. | GL does not track physical custody, drawers, counts, shipment state, or accountable operators. |
| **Keep cash inside Teller sessions** | Matches current teller workflows; low short-term complexity. | Does not support vault control, ATM cash, shipment workflows, or institution-wide cash positions. |
| **Create a separate Cash domain with location and movement subledger** | Clean custody model; aligns with module catalog; supports reconciliation and future denomination tracking. | Adds tables, commands, approvals, and reconciliation processes. |

---

## 4. Decision Outcome

**Chosen Option: Create a separate Cash domain with location and movement subledger.**

BankCORE will add a `Cash` domain for operational cash custody and inventory management. The model has three reconciled layers:

| Layer | Owner | Purpose |
| :--- | :--- | :--- |
| General Ledger | `Core::Ledger` | Financial position and reporting. |
| Cash location subledger | `Cash` | Accountable custody by branch, vault, drawer, ATM, or transit location. |
| Cash movement history | `Cash` | Append-oriented custody movement, count, adjustment, and lifecycle evidence. |

These layers are related but not interchangeable.

### 4.1 Core invariants

- GL balances are derived from immutable `journal_lines`.
- Cash location balances are derived from `cash_movements` and persisted as rebuildable snapshots.
- No controller may mutate cash balances directly.
- No `Cash` command may write `journal_entries` or `journal_lines` directly.
- Any cash operation with financial impact must create or reference an `OperationalEvent` and post through `Core::Posting`.
- Corrections must be compensating movements, counts, adjustments, or reversal events. Posted movements and posted journals must not be silently edited.
- Cash activity must use the current open business date per ADR-0018 unless a future ADR introduces branch-scoped business dates.

---

## 5. Domain Ownership

### 5.1 `Cash`

`Cash` owns:

- `cash_locations`
- `cash_movements`
- `cash_movement_lines` if denomination or multi-leg custody detail becomes necessary
- `cash_balances`
- `cash_counts`
- `cash_variances`
- cash reconciliation artifacts

Representative commands:

- `Cash::Commands::CreateLocation`
- `Cash::Commands::TransferCash`
- `Cash::Commands::RecordCashCount`
- `Cash::Commands::ApproveCashMovement`
- `Cash::Commands::PostCashVariance`
- `Cash::Commands::ReconcileCashLocation`

Representative queries:

- `Cash::Queries::CashPosition`
- `Cash::Queries::LocationActivity`
- `Cash::Queries::ReconciliationSummary`
- `Cash::Queries::PendingCashApprovals`

### 5.2 `Teller`

`Teller` continues to own teller sessions, expected cash, actual cash at close, and teller-session variance workflow. Teller sessions may reference a drawer `cash_location_id` once the Cash domain is implemented.

Teller cash deposits and withdrawals still record financial customer activity through existing operational event types such as `deposit.accepted` and `withdrawal.posted`.

**Resolved product decision:** [ADR-0039](0039-teller-session-drawer-custody-projection.md) defines how posted teller-channel cash operational events project into linked drawer **`cash_balances`**, while keeping the projection Cash-owned and separate from synthetic `cash_movements`. Teller **expected** cash remains session-owned per [ADR-0014](0014-teller-sessions-and-control-events.md) and is clarified by ADR-0039. Target operating semantics for branch cash layers remain in [301-branch-level-cash-tracking.md](../concepts/301-branch-level-cash-tracking.md) (see *Alignment with BankCORE implementation and roadmap*). Staff **where** tellers and supervisors initiate custody actions is covered by [ADR-0037](0037-internal-staff-authorized-surfaces.md).

### 5.3 `Workflow` and `Workspace`

`Workflow` should own reusable approval request and decision records once approval workflow tables exist. Until then, `Cash` commands may persist narrow approval fields on cash movement records.

`Workspace` owns operator identity and capability resolution. Cash commands may require capabilities such as future `cash.location.manage`, `cash.vault.transfer`, `cash.count.record`, or `cash.variance.approve`, but dual-control and no-self-approval remain command or workflow rules rather than capability codes.

### 5.4 Core domains

`Core::OperationalEvents` owns canonical business event records and event catalog metadata.

`Core::Posting` owns event-to-journal posting rules.

`Core::Ledger` owns GL accounts, journal entries, and journal lines.

---

## 6. Cash Locations

A cash location is an accountable container for physical or operational cash custody.

Initial location types:

```text
branch_vault
teller_drawer
internal_transit
```

Future location types:

```text
atm
external_transit
external_counterparty
```

Location attributes should include:

- location type
- operating-unit reference (`cash_locations.operating_unit_id`) using the `Organization` domain from ADR-0032
- responsible operator when applicable
- active/inactive state
- currency
- balancing requirement
- optional parent location
- optional external counterparty reference for future correspondent, Federal Reserve, carrier, or ATM processor use

External location modeling must not assume that one enum value is enough for every counterparty. A future implementation should prefer a counterparty reference when Fed or correspondent shipment workflows are implemented.

---

## 7. Cash Movements and Balances

All changes to cash location balances must originate from explicit cash movements, counts, or approved adjustments.

`cash_movements` should record:

- source location
- destination location
- amount in minor units
- currency
- business date
- initiating actor
- approving actor when required
- status
- reason code or movement type
- idempotency key for externally retried or UI-retried commands
- related `operational_event_id` when applicable
- related `posting_batch_id` or journal identifiers when applicable
- created timestamps and lifecycle timestamps

Movement status values should be local to the Cash domain and must not reuse `operational_events.status` semantics. Initial status values may include:

```text
pending_approval
approved
completed
cancelled
rejected
```

Transit or shipment lifecycle values such as `dispatched`, `in_transit`, `received`, `verified`, and `settled` are deferred until external shipment workflows are implemented.

`cash_balances` are persisted projections for performance and operator visibility. They are not independent truth. The system must be able to rebuild them from movement and count history.

---

## 8. Operational Events and Posting

Cash custody activity may be no-GL or GL-impacting.

No-GL custody events may be recorded as control or operational events and marked complete without journal lines, following the existing no-GL control-event posture.

GL-impacting events require posting rules in `Core::Posting`.

Candidate event families:

| Event type | GL impact | Phase |
| :--- | :--- | :--- |
| `cash.movement.completed` | No GL for internal transfers within institutional custody. | First Cash slice |
| `cash.count.recorded` | No GL by default. | First Cash slice |
| `cash.variance.posted` | GL adjustment for approved Cash-domain count variances; teller-session variance remains separate. | First Cash slice |
| `cash.shipment.sent` | GL impact when custody leaves internal cash and moves to an external settlement/counterparty asset. | Future |
| `cash.shipment.received` | GL impact when external cash is received into a branch vault. | Accepted follow-up: ADR-0035 |

Existing account `1110` represents physical cash under branch custody, including vaults and teller drawers. Internal movement between vault, drawer, and internal transit locations remains within `1110` and must not change aggregate GL cash.

Most external shipment accounting is intentionally deferred. ADR-0035 accepts the narrow inbound receipt path using `1130`; outbound shipment dispatch, shipment lifecycle state, settlement matching, and correction workflows remain future work. The seeded COA currently defines:

- `1110` as Cash in Vaults (teller drawers)
- `1120` as ACH Settlement
- `1130` as Due from Correspondent Banks

This ADR does not redefine `1120` as "Due from Federal Reserve." ADR-0035 uses `1130` for the accepted inbound receipt slice. Any broader Fed/correspondent shipment accounting still requires dedicated COA/GL mapping coverage before implementation.

---

## 9. Worked Examples

### 9.1 Vault replenishes teller drawer

Command:

```text
Cash::Commands::TransferCash
  source_location: branch vault
  destination_location: teller drawer
  amount_minor_units: 100000
  currency: USD
  business_date: current open day
  actor_id: teller or supervisor
  approval_actor_id: supervisor when vault policy requires it
```

Operational result:

- Create `cash_movement` for USD 1,000.00 from vault to drawer.
- Record `cash.movement.completed` with `channel: branch` or `teller`.
- Update rebuildable `cash_balances` in the same DB transaction.
- No GL posting, because the institution still holds the same cash and aggregate `1110` does not change.

Posting outline:

```text
No journal entry.
Subledger only:
  branch vault cash balance -100000
  teller drawer cash balance +100000
```

### 9.2 Teller drawer count variance

Command:

```text
Cash::Commands::RecordCashCount
  location: teller drawer
  counted_amount_minor_units: 99500
  expected_amount_minor_units: 100000
  business_date: current open day
  actor_id: teller
```

Operational result:

- Create a `cash_count`.
- Create a `cash_variance` for -500 minor units.
- If the variance exceeds policy, require supervisor approval.
- Approval records and posts `cash.variance.posted` for the Cash-domain count variance.

Posting outline:

```text
Shortage:
  Dr 5190 Teller Cash Over and Short  500
  Cr 1110 Cash in Vaults              500
```

This is conceptually aligned with ADR-0020, but event ownership remains separate: teller-session variance continues to use `teller.drawer.variance.posted`, while Cash-domain count variance uses `cash.variance.posted`.

### 9.3 Accepted external cash shipment receipt

ADR-0035 accepts a narrow receipt command for physical cash that has already arrived at an active branch vault.

Command:

```text
Cash::Commands::ReceiveExternalCashShipment
  destination_location: branch vault
  amount_minor_units: 5000000
  currency: USD
  business_date: current open day
  actor_id: branch supervisor or operations user
  external_source: Federal Reserve or correspondent bank
  shipment_reference: source shipment id
```

Operational result:

- Create a completed `cash_movement` with `movement_type: external_shipment_received`.
- Record and post `cash.shipment.received`.
- Increase branch vault custody balance through the Cash balance projector.

Posting outline:

```text
Dr 1110 Cash in Vaults
Cr 1130 Due from Correspondent Banks
```

### 9.4 Future external cash shipment dispatch

Command:

```text
Cash::Commands::DispatchExternalShipment
  source_location: branch vault
  destination_location: external counterparty or transit location
  amount_minor_units: 5000000
  currency: USD
  business_date: current open day
  actor_id: operations user
  approval_actor_id: second authorized user
```

Operational result:

- Create shipment movement with explicit lifecycle state.
- Record a financial operational event such as `cash.shipment.sent`.
- Post through `Core::Posting` only after the relevant GL account mapping has been accepted.

Possible posting outline, subject to future COA decision:

```text
Dr due-from external cash / settlement asset
Cr 1110 Cash in Vaults
```

This ADR does not choose the due-from account for Fed shipments.

---

## 10. Controls

Cash control requirements:

- Vault-involved movements require dual control.
- The approver must not be the same operator as the initiator.
- Cash commands must record actor, approval actor when applicable, branch/location context, business date, and timestamps.
- Movements that require approval must not change cash balances before approval.
- Counts and variances must be append-oriented and reviewable.
- EOD readiness should eventually include unresolved Cash-domain exceptions once the first Cash slice ships.
- Reconciliation queries must compare physical counts, cash subledger balances, and GL balances without allowing reconciliation rows to mutate source truth.

---

## 11. MVP Boundary and Phasing

### First Cash slice

The first implementation slice should include:

- `cash_locations` for branch vaults and teller drawers
- linking teller sessions to drawer cash locations
- internal vault-to-drawer and drawer-to-vault transfers
- cash counts for vault and drawer locations
- cash variance records and supervisor approval
- no-GL `cash.movement.completed` and `cash.count.recorded` event catalog entries
- `cash.variance.posted` through an explicit posting rule
- cash position and reconciliation queries
- read-only EOD warning evidence for unresolved Cash-domain exceptions

### Deferred

The following are post-MVP unless a selected branch story requires them earlier:

- ATM cash compartments and replenishment
- denomination, strap, bundle, roll, and coin tracking
- outbound external cash shipment dispatch
- carrier workflows, shipment lifecycle state, correction workflows, and settlement matching
- multi-branch or multi-entity cash accounting
- branch-scoped business dates
- cash forecasting and liquidity optimization
- advanced exception queues and case management

---

## 12. Technical Consequences

Positive:

- Gives BankCORE a proper custody model without weakening GL ownership.
- Supports branch vault and teller drawer reconciliation.
- Creates a path to ATM, denomination, and shipment workflows.
- Keeps cash controls aligned with OperationalEvent, Posting, Ledger, BusinessDate, Teller, Workflow, and Workspace boundaries.

Negative:

- Adds another operational subledger and rebuildable balance projection.
- Requires careful reconciliation between `cash_balances` and GL `1110`.
- Introduces approval and lifecycle state that must be tested across commands.
- External shipment accounting cannot be completed until GL mapping is explicitly decided.

Neutral:

- Existing teller deposit, withdrawal, transfer, and session behavior remains valid.
- `cash_balances` are performance projections, not a second accounting ledger.
- Cash denomination support can be added later without changing the first aggregate amount flow.

---

## 13. Risks and Mitigations

| Risk | Mitigation |
| :--- | :--- |
| Cash subledger becomes a second GL | Keep GL reporting derived only from `journal_lines`; cash balances are custody projections. |
| Internal transfers accidentally post GL | Explicitly mark internal vault/drawer/transit movement as no-GL while remaining within `1110`. |
| Existing COA meanings drift | Do not redefine `1120`; ADR-0035 uses `1130` for inbound receipt and future shipment accounting needs explicit ADR coverage. |
| Balance snapshots become independent truth | Require rebuild from movements and counts; test rebuild equivalence. |
| Dual control is implemented as broad roles only | Use capability checks only for attempt authorization; enforce no-self-approval and thresholds in Cash/Workflow commands. |
| Teller and Cash both own drawer truth | Teller owns session lifecycle; Cash owns location custody and location balances; link records rather than duplicating responsibility. |

---

## 14. Open Questions

1. Should later vault/drawer transfer variants continue using one generic `cash.movement.completed` event type or introduce specific types such as `cash.vault.transfer.completed`?
2. Should teller-session drawer variance ever migrate from `teller.drawer.variance.posted` into Cash, or remain permanently separate?
3. Should `cash_balances` be one row per location/currency or include a balance kind for future denomination and compartment projections?
4. What operator capability codes should be seeded for cash movement, cash count, vault approval, and variance approval?
5. Should EOD readiness eventually block on unresolved cash counts/variances, or remain read-only evidence?
6. Which additional GL accounts or settlement records are needed for outbound shipment dispatch, settlement matching, and correction workflows?

---

## 15. Decision Summary

BankCORE will model cash inventory and management in a dedicated `Cash` domain.

The Cash domain tracks operational custody through cash locations, movements, counts, variances, and rebuildable balance snapshots. GL remains the financial truth, and any financial impact must flow through `Core::OperationalEvents` and `Core::Posting`.

The first slice is branch-safe cash control: vaults, teller drawers, internal transfers, counts, variances, reconciliation, and read-only EOD warning evidence. ADR-0035 adds a narrow inbound external shipment receipt path. ATM cash, denomination tracking, outbound external shipment lifecycle, settlement matching, and EOD cash blocking policy remain follow-up decisions.
