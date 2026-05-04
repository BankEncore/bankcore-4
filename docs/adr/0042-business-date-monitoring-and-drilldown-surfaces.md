# ADR-0042: Business-date monitoring and drilldown surfaces

**Status:** Proposed  
**Date:** 2026-05-03  
**Decision Type:** Internal workspace read model / monitoring surface / drilldown contract  
**Aligns with:** [ADR-0016](0016-trial-balance-and-eod-readiness.md), [ADR-0018](0018-business-date-close-and-posting-invariant.md), [ADR-0025](0025-internal-workspace-ui.md), [ADR-0026](0026-branch-csr-servicing.md), [ADR-0031](0031-cash-inventory-and-management.md), [ADR-0032](0032-operating-units-and-branch-scope.md), [ADR-0037](0037-internal-staff-authorized-surfaces.md), [ADR-0038](0038-account-balance-projections-and-daily-snapshots.md), [ADR-0039](0039-teller-session-drawer-custody-projection.md), [ADR-0041](0041-close-package-and-eod-classification-taxonomy.md)

---

## 1. Context

BankCORE now ships enough T4 read depth that operators can inspect the current open business date, review close readiness, search operational events, inspect posting and journal detail, and review cash approvals and reconciliation evidence.

Those surfaces exist today, but they are still somewhat fragmented:

- the internal header shows the current business date
- Ops close package is the canonical EOD hub
- Ops operational event search and detail provide the deepest event-to-posting traceability
- Branch event search and detail provide teller and CSR-adjacent visibility
- cash monitoring and teller-session monitoring live on separate surfaces

The remaining gap is not a lack of raw data. The gap is a lack of one explicit BankCORE contract for how an operator answers:

- What is the current open business date?
- Is it still open for posting?
- Why is it or is it not ready to close?
- How do I drill from a summary number to the authoritative record and then to financial truth?

Without that contract, the same data risks being shown inconsistently across Ops and Branch. Contributors may also introduce generic snapshot dashboards that do not respect BankCORE's existing business-date, cash-custody, and posting boundaries.

---

## 2. Decision Drivers

- Keep the monitored "current date" anchored to the singleton `current_business_on` model from ADR-0018.
- Preserve Ops close package as the canonical institution-level open-day control surface.
- Make every summary number explainable, traceable, and reconstructable from existing durable records.
- Avoid inventing a second status model or duplicating domain truth in UI-only snapshot tables.
- Respect domain ownership differences between operational events, teller sessions, cash custody, and ledger posting.
- Keep Branch monitoring branch-friendly without implying branch-scoped business dates or branch-level books.
- Standardize drill links so new T-family slices can plug into the same operator experience.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **A. Make Ops close package the canonical business-date monitoring surface and define a drilldown contract around existing truth models** | Fits current ADRs and shipped screens; low risk; preserves domain truth; extends naturally as new families ship. | Requires discipline to keep links and filters consistent across surfaces. |
| **B. Add a new generic snapshot dashboard shared by Branch and Ops** | Centralizes visual summaries. | Risks creating a parallel interpretation layer disconnected from close policy, cash truth, and event traceability. |
| **C. Make Branch the primary "today" dashboard and treat Ops as a back-office detail area** | Familiar to branch users. | Conflicts with institution-wide singleton business date and current close authority in Ops. |
| **D. Persist new snapshot/materialized monitoring tables before standardizing the UI contract** | Could improve future scale and analytics. | Premature for current scope; adds second-source-of-truth risk before the navigation and drill model is settled. |

---

## 4. Decision Outcome

**Chosen option: A. Make Ops close package the canonical business-date monitoring surface and define a drilldown contract around existing truth models.**

BankCORE will treat "current date monitoring" as **business-date monitoring**, not as a generic branch activity dashboard.

The canonical monitored date is the singleton **open business date** from ADR-0018:

- `current_business_on` is the institution-wide open day
- historical dates are reviewable but retrospective-only
- Branch and Ops may both show the current business date, but only Ops owns the authoritative close-control surface

### 4.1 Canonical Level 0 question

The top-level monitoring question is:

> What is the current open business date, what is its current control state, and what evidence explains that state?

This is not the same as:

- "What happened today by wall clock?"
- "What happened at this branch only?"
- "What are today's teller KPIs?"

Those may be useful supporting views, but they are subordinate to the business-date control model.

### 4.2 Standard drilldown levels

BankCORE will use these drilldown levels consistently for business-date monitoring.

#### Level 0: Control surface

Primary home:

- `ops/close_package`

Required summary facts:

- reviewed `business_date`
- `current_business_on`
- whether the reviewed day is the current open day or a historical closed day
- `eod_ready`
- current blocker and warning counts
- classification bucket counts from ADR-0041

Branch may expose a smaller "today" status panel, but it is informational and must link back to the Ops close package for authoritative close review.

#### Level 1: Bucket or control-specific drill entry

Every summary count or state on the control surface should drill to one of these entry types:

- filtered operational-event index
- teller-session queue or list
- cash approval or reconciliation view
- hold list
- trial balance detail
- close history

Not every metric drills to operational events. Cash custody and teller-session workflow must remain visible through their native truth models.

#### Level 2: Record index

Each drill entry lands on a filtered index that clearly states the active business-date and scope filters.

Examples:

- pending events for `business_date = current_business_on`
- reversed events for `business_date = current_business_on`
- active holds linked to deposits accepted on `business_date = current_business_on`
- teller sessions still `open` or `pending_supervisor`
- cash movements pending approval for the operator's current `operating_unit_id`

#### Level 3: Canonical record detail

The user must then be able to open the authoritative detail page for the selected row:

- operational event detail
- teller session detail or approval row
- cash movement, cash count, or cash variance detail
- close-event detail where applicable

#### Level 4: Financial or custody truth

From the canonical record, the user drills to the truth artifact appropriate to that domain:

- posting batch
- journal entry
- journal lines
- cash movement chain
- count and variance evidence

Operational-event-backed money movement uses the posting and journal path. Cash-custody issues use the Cash-domain path and must not be flattened into an events-only story.

### 4.3 Explainability contract

Every number shown on a business-date monitoring surface must be:

- explainable
- traceable
- reconstructable

Concretely, each displayed metric must have a documented source query and a drill path to a durable record set.

UI-only counters without an inspectable underlying record set are not acceptable for close-control screens.

### 4.4 Metric definition contract

Each displayed metric must have a documented metric definition even if the UI does not expose that definition in full by default.

A metric definition must declare:

- owning query, service, or source model
- time-scope type
- required filters
- grouping or aggregation logic
- primary drill target

Examples:

- `pending_operational_events_count`
  - owner: `Teller::Queries::EodReadiness`
  - time scope: business-date scoped
  - filters: `business_date = reviewed business_date`, `status = pending`
  - aggregation: count of matching operational events
  - drill target: Ops operational event search filtered to the same date and status

- `open_teller_sessions_count`
  - owner: `Teller::Queries::EodReadiness`
  - time scope: session-lifecycle scoped
  - filters: session `status IN (open, pending_supervisor)`
  - aggregation: count of matching teller sessions
  - drill target: teller-session queue or list with the same status filter

- `pending_cash_movements_count`
  - owner: readiness or Cash-domain support query as applicable
  - time scope: real-time state scoped
  - filters: movement approval state and applicable operating-unit scope
  - aggregation: count of matching pending cash movements
  - drill target: Cash approvals list

This contract is part of the read-model design. It is not a requirement to persist metric-definition rows in the database.

### 4.5 Time-scope classification

Not every monitored number is scoped the same way. Monitoring surfaces must declare the time-scope semantics of each metric rather than assuming all values mean "activity on the business date."

BankCORE will use these time-scope categories:

- `business-date scoped`
  - activity whose primary meaning is "records stamped to the reviewed business date"
  - examples: pending operational events, posted operational events, trial balance activity

- `session-lifecycle scoped`
  - activity whose primary meaning is tied to teller-session state rather than only the business-date stamp
  - examples: open sessions, pending-supervisor sessions, session close attempts, drawer variance review

- `real-time state scoped`
  - activity whose primary meaning is current operational state at the moment of review
  - examples: pending cash movements, unresolved cash variances, active holds where the primary question is whether the hold is active now

When a metric mixes concerns, the metric definition must state which scope is primary and why.

---

## 5. Surface Responsibilities

### 5.1 Ops responsibilities

Ops owns institution-level business-date control and close monitoring.

Canonical Ops screens:

- `ops/close_package`
- `ops/operational_events`
- `ops/exceptions`
- `ops/cash`
- `ops/teller_variances`
- `ops/eod` and `ops/business_date_close` as legacy or supporting screens

Ops is responsible for:

- current open-day status
- close eligibility
- institution-wide blockers and warnings
- classified close evidence
- deep event-to-posting traceability
- retrospective review of historical business dates

For event-backed monitoring, Ops operational event search is the canonical Level 2 hub. Event-backed metrics should converge on that index with consistent filters rather than inventing one-off drill lists per screen.

### 5.2 Branch responsibilities

Branch owns branch-staff situational awareness and action entry points, not institution-level day-close authority.

Branch may show:

- current business date banner or compact status card
- teller-session counts
- pending supervisor items relevant to branch staff
- shortcuts into branch event search, cash position, and servicing

Branch should not become a second close package. If Branch shows a current-day summary, it must link operators into the authoritative Ops drill path for close-state review.

### 5.3 Scope responsibilities

Branch-facing monitoring and filtering should use `operating_unit_id`, not `branch_id`, per ADR-0032.

This ADR does not introduce:

- branch-scoped business dates
- branch-level ledger partitions
- branch-level `eod_ready`

Institution-wide close remains anchored to the singleton model.

---

## 6. Drill-Link Contract by Bucket

The following contract standardizes where Level 1 links should land.

### 6.1 Blockers

`journal_totals_balanced = false`

- drill target: trial balance detail on the reviewed business date
- future enhancement: explicit imbalance evidence query if trial-balance-only view proves too coarse

`open_teller_sessions_count` or `pending_supervisor` sessions

- drill target: teller-session list filtered to open and pending-supervisor states
- primary record: teller session
- financial follow-up: expected cash, close attempt, variance approval evidence

`pending_operational_events_count`

- drill target: Ops operational event search filtered by `business_date` and `status = pending`
- primary record: operational event
- financial follow-up: posting batch and journals when posted later

### 6.2 Warnings

`pending_cash_movements_count`

- drill target: cash approvals list filtered to pending approvals
- primary record: cash movement

`unresolved_cash_variances_count`

- drill target: cash reconciliation or variance review list
- primary record: cash variance

### 6.3 Classification buckets from ADR-0041

`posted`

- drill target: Ops operational event search filtered by `business_date` and posted statuses or posted families

`pending`

- drill target: Ops operational event search filtered by `business_date` and `status = pending`

`reversed`

- drill target: Ops operational event search filtered by `business_date` and reversal event families

`held`

- drill target: hold index filtered to active holds relevant to the reviewed business date
- if event-linked, hold detail should link back to the originating operational event

`overridden`

- drill target: Ops operational event search filtered to override event families

`exception`

- drill target: Ops operational event search or exception queue filtered to abnormal event families such as `overdraft.nsf_denied`

### 6.4 Raw breakdowns

Status, channel, and event-type counts on the close package should also be clickable where practical and land on the operational-event index with matching filters applied.

### 6.5 Event-backed metrics hub rule

For metrics whose authoritative underlying record set is operational events, the default Level 2 landing surface is the Ops operational event index.

That index should remain the primary hub for:

- date-scoped event review
- support-key search
- pivots by status, channel, and event type
- links into operational-event detail
- links onward into posting and journal truth

Specialized screens may still exist for operator workflow reasons, but they should not fragment the event-backed monitoring model when the operational-event index can express the same filtered record set.

---

## 7. Record Detail Contract

### 7.1 Operational event detail

Ops operational event detail is the canonical trace depth for event-backed monitoring.

It should remain the reference implementation for:

- event metadata
- actor and teller-session attribution
- account context
- reversal links
- posting batches
- journal entries
- journal lines

Branch event detail may remain role-appropriate and action-oriented, but it should not diverge materially from the Ops trace model where the same event is being explained.

### 7.2 Teller-session detail

Teller-session drilldown should explain:

- operating unit
- operator
- opened and closed timestamps
- expected cash
- actual cash
- variance
- supervisor approval state

This truth path is teller-session and cash-control oriented, not journal-first.

### 7.3 Cash detail

Cash monitoring should drill through Cash-owned records:

- cash location
- movement
- count
- variance
- approval decision
- reconciliation summary

Where a cash event also creates an operational event or GL effect, cross-links are useful, but the cash record remains the operational source of truth for custody review.

---

## 8. UI Guidance

### 8.1 Internal header

The existing internal header business-date indicator should remain, but it is only context, not the monitoring surface.

### 8.2 Branch "today" card

Branch should gain a small current-day control card near the dashboard top with:

- current business date
- open sessions count
- pending supervisor count
- link to Branch events for today
- link to Cash position
- link to Ops close package for full close-state review

This gives branch staff orientation without duplicating close-package logic.

### 8.3 Ops close package

Ops close package should become more obviously drillable by making bucket counts and blocker/warning rows link to their target indexes or lists.

The close package should stay institution-focused, not branch-themed.

### 8.4 Explainability UI pattern

When a user drills from a summary number, the destination screen should make the number's definition legible.

This may be as simple as showing:

- active filters
- reviewed business date
- record count
- grouping dimension if grouped

Later slices may expose an explicit "Explain this number" action, but the minimum requirement is that the destination screen reveals how the metric was formed.

---

## 9. Implementation Sequence

### Phase 1: Make current business-date monitoring explicit

- keep `ops/close_package` as canonical
- add clearer current open-day language where needed
- add branch-facing compact status panel linking to Ops close package

### Phase 2: Finish bucket drill links

- make close-package blocker, warning, and bucket counts clickable
- standardize query params used by each link target
- make raw status/channel/type counts link into event search

### Phase 3: Tighten record detail parity

- keep Ops event detail as canonical
- improve Branch event detail where key trace fields are missing
- add or improve native teller-session and Cash drill surfaces where counts currently dead-end

### Phase 4: Strengthen scope-aware filtering

- extend relevant event and support screens with better `operating_unit_id` filtering where the underlying records support it
- preserve the distinction between operating-unit filtering and institution-level close authority

### Phase 5: Optional later enhancements

- export of filtered drill results
- saved support views
- explicit "explain this number" actions backed by the same drill contract
- additional read models or materialized summaries only after the interaction contract is proven

### Phase 6: Future performance strategy if volume requires it

- define thresholds for when event-backed monitoring queries need materialization, caching, or alternate read models
- preserve the metric-definition and drill contracts when introducing performance optimizations
- avoid introducing opaque aggregates that break explainability or detach counts from inspectable record sets

---

## 10. Consequences

### Positive

- Operators get one clear answer to "what day are we on and why is it in this state?"
- Existing close, event, and cash surfaces become navigationally coherent without new domain persistence.
- New transaction families can plug into an existing drill model instead of inventing one-off dashboards.

### Negative

- Some current screens will need link and filter cleanup before the experience feels complete.
- Contributors must preserve the distinction between event-backed truth and cash-custody truth.

### Neutral

- This ADR does not change close policy, posting rules, or business-date invariants.
- This ADR does not require new persisted snapshot tables in its first slice.

---

## 11. References to current implementation

- Internal header business date: `app/views/layouts/internal.html.erb`
- Canonical open-day control surface: `app/views/ops/close_packages/show.html.erb`
- Legacy EOD support screen: `app/views/ops/eod/index.html.erb`
- Ops event index: `app/views/ops/operational_events/index.html.erb`
- Ops event detail: `app/views/ops/operational_events/show.html.erb`
- Branch dashboard: `app/views/branch/dashboard/index.html.erb`
- Branch event index: `app/views/branch/operational_events/index.html.erb`
- Branch event detail: `app/views/branch/operational_events/show.html.erb`
- Ops exceptions: `app/views/ops/exceptions/index.html.erb`
- Branch cash position: `app/views/branch/cash/index.html.erb`
- Ops cash monitoring: `app/views/ops/cash/index.html.erb`
