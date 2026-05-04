# ADR-0042: Business-date monitoring and drilldown surfaces

**Status:** Accepted  
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
  - drill target: `Ops::TellerSessionsController#index` with the same status filter (canonical Level 2 once implemented; see §4.6)

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

### 4.6 Implementation resolutions (binding)

The following rules constrain HTML and shared-query work that implements this ADR. They do not change close policy, posting rules, or `eod_ready` composition.

**Operational event listing (`ListOperationalEvents`)**

- Extensions are **additive only**: default behavior, ordering, pagination, and single-`event_type` filtering remain unchanged when new params are omitted.
- **`event_type_in`** (multi-value filter) uses repeated query parameters, for example  
  `event_type_in[]=override.requested&event_type_in[]=override.approved`.
- A request must **not** supply both **`event_type`** and **`event_type_in`**; respond with **`422 invalid_request`** (ambiguous drill semantics).
- Normalize **`event_type_in`**: strip blanks, de-duplicate, cap at **10** types; if the normalized list is empty, treat the filter as **absent**.
- Validation for **`event_type_in`** applies **only** when that param is supplied.
- Callers include **Ops HTML**, **Branch HTML**, and **Teller JSON-backed** read paths. Do not tighten the shared query in ways that break existing account-activity or teller event listing behavior.
- **Teller JSON** does not need to expose **`event_type_in`** in the first implementation slice unless explicitly chosen; controllers may continue permitting **`event_type`** only there.

**Cash warning drills**

- **`pending_cash_movements_count`** may drill to **`ops/cash`** when that screen already surfaces pending movements matching the metric intent.
- **`unresolved_cash_variances_count`** remains **non-drillable** until a destination exposes the **same filtered record set** (reviewed business date and statuses) as the readiness count.
- Do not make a warning **clickable** unless the landing screen explains the **same underlying record set** as the count (see §4.3 and §8.4).

**Ops teller sessions**

- **`Ops::TellerSessionsController#index`** is the canonical **Level 2** teller-session drill surface.
- Default index filter: **`status IN (open, pending_supervisor)`**; default ordering: **`opened_at`**, then **`id`**.
- **`#show`** should present at minimum: status, operator, operating unit, drawer code, cash location, `opened_at`, `closed_at`, `opening_cash_minor_units`, `expected_cash_minor_units`, `actual_cash_minor_units`, `variance_minor_units`, supervisor operator, and **`supervisor_approved_at`** (field names align to persisted columns as implemented).
- Close-package session blockers and session lists link here once the controller exists.
- **Same-page anchors** on the close package are **not** part of the long-term drill contract.

**Held bucket**

- The **`held`** bucket may remain **informational** (no Ops holds index) until after Ops teller-session pages ship; **event-backed** buckets and **raw** event breakdown drills take priority.
- Revisit **`Ops::HoldsController#index`** after teller-session drills are canonical.

**Branch `operating_unit_id` filtering**

- When Branch event search applies **`operating_unit_id`**, the active scope must be **visible** in the UI; **no** hidden narrowing.
- Provide **“Show all units”** (or equivalent) to clear the filter.
- Branch-scoped views do **not** change institution-level **`eod_ready`** or close authority.

**Explainability minimum**

- Drill destinations must show the **reviewed business date** (when supplied by the drill) and **active filters** in visible copy, not only in form fields.
- **Ops event search:** keep and reinforce the existing envelope/context line.
- **Ops cash** and future Ops holds/session indexes: add a short **filter/context banner** when reached from close-package drills.

**Authorization**

- New Ops teller-session pages follow existing **`Ops::ApplicationController`** posture (e.g. **`require_ops_operator!`**). No extra capability gate unless product explicitly adds one.
- If **`operating_unit_id`** is accepted on Ops or Branch event search, validate it against operating units the operator may legitimately scope (**no** arbitrary-ID probing).

**Navigation**

- For metrics backed by operational events, the default Level 2 landing remains **`ops/operational_events`** (§6.5).
- For the **exception** classification bucket, the default drill is **`ops/operational_events`** with **`business_date`** and **`event_type=overdraft.nsf_denied`**. **`ops/exceptions`** remains a **workflow queue**, not the canonical Level 2 hub for that bucket count.

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

- drill target: **`Ops::TellerSessionsController#index`** with default filter `status IN (open, pending_supervisor)` (ships in implementation Phase 3; until then, session blockers on the close package stay non-clickable rather than using anchor-only bridges as the long-term contract)
- primary record: teller session
- financial follow-up: expected cash, close attempt, variance approval evidence

`pending_operational_events_count`

- drill target: Ops operational event search filtered by `business_date` and `status = pending`
- primary record: operational event
- financial follow-up: posting batch and journals when posted later

### 6.2 Warnings

`pending_cash_movements_count`

- drill target: **`ops/cash`** when that screen already presents pending movements consistent with the readiness count
- primary record: cash movement

`unresolved_cash_variances_count`

- drill target: **none** until a reconciliation or variance list exposes the **same** filtered record set as the readiness count for the reviewed business date (until then, display as informational only; see §4.6)
- primary record: cash variance (conceptual)

### 6.3 Classification buckets from ADR-0041

`posted`

- drill target: Ops operational event search filtered by `business_date` and posted statuses or posted families

`pending`

- drill target: Ops operational event search filtered by `business_date` and `status = pending`

`reversed`

- drill target: Ops operational event search filtered by `business_date` and reversal event families

`held`

- drill target: hold index filtered to active holds relevant to the reviewed business date (**may remain informational** until an Ops holds index exists; §4.6)
- if event-linked, hold detail should link back to the originating operational event

`overridden`

- drill target: Ops operational event search with **`event_type_in`** covering `override.requested` and `override.approved` for the reviewed **`business_date`** (see §4.6); Ops search form multi-select for `event_type_in` is optional

`exception`

- drill target (default): Ops operational event search with **`business_date`** and **`event_type=overdraft.nsf_denied`**
- **`ops/exceptions`** remains a workflow queue, **not** the canonical Level 2 hub for this bucket count

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

The canonical Level 3 surface for teller-session drills from the close package is **`Ops::TellerSessionsController#show`** (Level 2 is **`#index`** per §6.1).

It should explain at minimum:

- status
- operator
- operating unit
- drawer code and cash location
- opened and closed timestamps
- **opening**, **expected**, and **actual** cash (minor units as persisted)
- variance (minor units)
- supervisor operator and **`supervisor_approved_at`**

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

**Minimum (binding for implementation):** show **reviewed business date** (when supplied by the drill) and **active filters** in **visible copy**, not only embedded in form fields. Reinforce the Ops operational-event search envelope line; for **`ops/cash`** and future Ops holds or teller-session indexes reached from drills, add a short **filter/context banner**.

Additionally helpful:

- record count
- grouping dimension if grouped

Later slices may expose an explicit "Explain this number" action, but the minimum requirement is that the destination screen reveals how the metric was formed.

---

## 9. Implementation Sequence

### Phase 1: Make current business-date monitoring explicit

- keep `ops/close_package` as canonical
- add clearer current open-day language where needed (reviewed date vs `current_business_on`)
- add branch-facing compact status panel linking to Ops close package (and Branch events / cash as in §8.2)

### Phase 2: Finish bucket drill links (event-backed first)

- make **event-backed** classification buckets and **raw** status/channel/event-type breakdown counts clickable into **`ops/operational_events`** with standardized params (including **`event_type_in`** for the overridden bucket per §4.6)
- **`pending_cash_movements_count`** may drill to **`ops/cash`** when consistent with the metric
- **`unresolved_cash_variances_count`** and **`held`** remain **informational** until matching destinations exist (§4.6)
- **session-related blockers** remain **non-clickable** until **`Ops::TellerSessionsController`** ships in Phase 3

### Phase 3: Tighten record detail parity and canonical session drills

- keep Ops event detail as canonical; improve Branch event detail where key trace fields are missing
- ship **`Ops::TellerSessionsController#index`** and **`#show`** per §4.6 and §7.2; wire close-package session blockers and session lists to these routes
- remove or ignore any temporary anchor-only bridges once session pages exist
- revisit whether **`Ops::HoldsController#index`** is required immediately or can follow

### Phase 4: Strengthen scope-aware filtering

- extend relevant event and support screens with **`operating_unit_id`** filtering where records support it; validate scope server-side (**no** arbitrary-ID probing per §4.6)
- Branch: visible active scope and **“Show all units”** (or equivalent); preserve distinction between operating-unit filtering and institution-level close authority

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
- Ops teller sessions: `app/controllers/ops/teller_sessions_controller.rb`, `app/views/ops/teller_sessions/index.html.erb`, `app/views/ops/teller_sessions/show.html.erb`
- Branch cash position: `app/views/branch/cash/index.html.erb`
- Ops cash monitoring: `app/views/ops/cash/index.html.erb`
