# ADR-0041: Close package and EOD classification taxonomy

**Status:** Accepted  
**Date:** 2026-05-03  
**Decision Type:** Operational read model / close evidence taxonomy / EOD interpretation  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0013](0013-holds-available-and-servicing-events.md), [ADR-0016](0016-trial-balance-and-eod-readiness.md), [ADR-0018](0018-business-date-close-and-posting-invariant.md), [ADR-0019](0019-event-catalog-and-fee-events.md), [ADR-0031](0031-cash-inventory-and-management.md), [ADR-0037](0037-internal-staff-authorized-surfaces.md), [ADR-0039](0039-teller-session-drawer-custody-projection.md), [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md)

---

## 1. Context

BankCORE already ships a narrow close and readiness surface:

- `Teller::Queries::EodReadiness` computes whether the current business date is eligible for close.
- Ops close-package screens show trial balance, recent close history, pending operational events, and open or pending-supervisor teller sessions.
- Cash-domain pending approvals and unresolved variances are exposed today as non-blocking readiness warnings.

That shipped surface is useful but still low-level. It exposes raw counts and point-in-time evidence, but it does not yet provide a stable close-package taxonomy that groups operational evidence into consistent, bank-operator-facing buckets such as posted, pending, reversed, held, overridden, exception, blocker, and warning.

Phase T4 needs that classification layer so new transaction families, including T1 `check.deposit.accepted`, can appear in the close package through a consistent read model without immediately changing close policy or introducing new workflow persistence.

This ADR describes **T4.1**, the first implementation slice of the broader T4 roadmap category.

This ADR defines the initial close-package and EOD classification taxonomy. It does not add a workflow engine, new operational-event statuses, new persisted classification rows, or new close blockers.

---

## 2. Decision Drivers

- Improve operator readability of close evidence without changing the existing close gate by accident.
- Keep close classification derived from existing rows and query logic rather than adding a second persistence model.
- Support new transaction families, including held check deposits and reversal activity, through stable read-model categories.
- Preserve the current business-date close policy while making non-blocking warnings and exception evidence more legible.
- Avoid overloading `operational_events.status` with close-package semantics that belong in query interpretation.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **A. Derived read-model taxonomy with no close-gate change** | Lowest risk; rebuildable from existing truth; adds operator-facing structure without workflow churn; easy to extend for new families. | Classification logic lives in query code and must stay disciplined as new families are added. |
| **B. Derived taxonomy plus immediate new close blockers** | Stronger operational posture; can make warnings enforceable immediately. | Couples presentation and policy; risks changing close behavior before evidence and operator experience are proven. |
| **C. Persisted classification rows / queue tables** | Durable queueing and assignment foundation; easier future workflow routing. | Too heavy for T4; adds a second source of truth for derived operational state; larger migration and support burden. |
| **D. Keep only raw counts by status/channel/type** | Lowest implementation effort. | Does not solve the close-package readability problem and does not scale well as new transaction families appear. |

---

## 4. Decision Outcome

**Chosen option: A. Derived read-model taxonomy with no close-gate change.**

BankCORE will implement T4 as a derived close-package classification layer over existing operational events, holds, teller sessions, Cash-domain records, and readiness outputs.

T4 introduces a canonical bucket set for close-package reporting, but it does not change the authoritative `eod_ready` gate in this slice.

### 4.1 Taxonomy purpose

The T4 taxonomy is a read-model interpretation used for:

- close-package summaries
- grouped close evidence
- exception review
- future extension of operational families into consistent close-package buckets

The taxonomy is not a persisted status model and does not replace `operational_events.status`, teller-session statuses, hold statuses, or Cash-domain statuses.

### 4.2 Canonical buckets

T4 defines these close-package classification buckets:

- `posted`
- `pending`
- `reversed`
- `held`
- `overridden`
- `exception`
- `blocker`
- `warning`

Every bucket is a read-side grouping, not a new persisted state.

Close-package classification is also not a single persisted status system. For summary rollups in T4.1, each evidence row should contribute to one primary classification bucket. Detailed views may still show linked context or secondary tags across related evidence. For example, a posted check deposit contributes to `posted`, while an active linked hold on that deposit contributes separately to `held`.

### 4.3 Bucket meanings

#### `posted`

Durable events that have successfully posted or otherwise represent completed immutable evidence under their native model.

Examples:

- posted financial operational events
- posted no-GL operational events that are complete under their family semantics

#### `pending`

Durable work recorded but not yet completed under its native workflow.

Examples:

- `operational_events.status = pending`

#### `reversed`

Reversal activity represented by reversal events themselves.

T4 does **not** classify the original event row as a synthetic new “reversed status.” Instead, reversal evidence appears through the reversal event and its linkage to the original row.

Examples:

- `posting.reversal`

#### `held`

Active holds that reduce available balance.

In T4.1, `held` is informational evidence only. It does not automatically become a warning or blocker.

Examples:

- active `holds` rows, including deposit-linked and check-deposit-linked holds

#### `overridden`

Override request or approval evidence recorded through the existing operational-event family.

In T4.1, overrides are informational evidence only unless a separate ADR later promotes specific override states into close policy.

Examples:

- `override.requested`
- `override.approved`

#### `exception`

Operationally abnormal evidence that deserves review but is not, by itself, a close blocker and is not part of the current `EodReadiness` warning channel in T4.1.

Examples:

- `overdraft.nsf_denied`

#### `blocker`

Facts that make close ineligible under the existing readiness gate.

T4.1 does not invent new blockers. It reports the blockers already implied by `Teller::Queries::EodReadiness`.

In T4.1, `blocker` is defined exactly by the current readiness conjuncts behind `eod_ready`:

- journal totals not balanced
- one or more teller sessions still `open` or `pending_supervisor`
- one or more operational events still `pending`

Examples:

- journal imbalance
- open teller sessions
- pending-supervisor teller sessions
- pending operational events

#### `warning`

Non-blocking evidence that requires operator attention but does not prevent close in T4.1.

T4.1 preserves current warning posture for Cash-domain concerns that the system already surfaces as warnings through `Teller::Queries::EodReadiness`.

Examples:

- pending cash movements
- unresolved cash variances
- future non-blocking close evidence explicitly mapped by query rule

### 4.4 Close-gate policy

T4.1 does not change close eligibility rules.

`Teller::Queries::EodReadiness` remains authoritative for `eod_ready` and current close blockers. The classification taxonomy may explain those blockers more clearly, but it must not silently expand or narrow close policy in this slice.

Any future change that promotes warnings, holds, overrides, or new event families into formal close blockers requires a separate ADR or an amendment to this one.

For the current open business date, `blocker` is actionable live close ineligibility. For historical business dates where `posting_day_closed` is true, the same classifications remain useful as retrospective evidence, but they should be presented as explanatory close-package history rather than as a live close gate.

### 4.5 Derived query only

T4.1 uses derived query logic only.

It does not add:

- a close-package classification table
- a workflow queue table
- new status columns on operational events, holds, teller sessions, or Cash rows

The classification layer is intentionally rebuildable from existing persisted facts.

### 4.6 Family extension rule

New transaction families extend the close-package taxonomy by mapping their existing evidence into one or more canonical buckets.

Examples:

- T1 `check.deposit.accepted` may appear as `posted`
- active holds linked to deposited checks may appear as `held`
- `posting.reversal` for a check deposit may appear as `reversed`

New families should map into this taxonomy through read-model rules rather than by adding ad hoc close-package-only statuses.

---

## 5. Consequences

### Positive

- Ops close-package screens gain a stable classification vocabulary without changing existing close policy.
- New families such as check deposits, linked holds, and reversal activity can be integrated into close evidence coherently.
- The model remains derived and rebuildable from durable truths already owned by existing domains.

### Negative

- Classification rules must be maintained carefully as more families are added.
- Some operators may initially expect `held` or `exception` evidence to block close even though T4.1 keeps them informational or warning-only.

### Neutral

- A later ADR may still introduce persisted exception queues, assignment, or workflow routing if operational review depth grows.
- A later ADR may still promote some warnings or exceptions into formal close blockers.

---

## 6. Initial Mapping Guidance

The first implementation should map existing evidence like this:

- `posted`
  - posted operational events relevant to the reviewed business date
- `pending`
  - pending operational events for the reviewed business date
- `reversed`
  - reversal events for the reviewed business date
- `held`
  - active holds present when the close package is generated for the reviewed business date and linked either to operational events on that business date or to hold-placement activity recorded on that business date
- `overridden`
  - override request and approval events for the reviewed business date
- `exception`
  - `overdraft.nsf_denied`
- `blocker`
  - readiness failures already enforced by `EodReadiness`
- `warning`
  - current non-blocking cash warnings already surfaced by `EodReadiness`, including pending cash movements and unresolved cash variances

The exact read-side grouping query may evolve, but the bucket meanings above should remain stable unless another ADR changes them.

---

## 7. Explicit Deferrals

T4.1 does **not** add:

- new close blockers
- a workflow or assignment engine
- persisted close-package queue rows
- new event types solely for close-package presentation
- synthetic “reversed” statuses on original operational-event rows
- automatic promotion of `held` evidence into warnings or blockers
- branch-scoped business-date policy changes

---

## 8. Implementation (T4.1 shipped)

Normative **`eod_ready`** composition and **`CloseBusinessDate`** gating remain **[ADR-0016](0016-trial-balance-and-eod-readiness.md)** and **[ADR-0018](0018-business-date-close-and-posting-invariant.md)**; this slice adds interpretation and Ops UX only.

- **Query:** `Teller::Queries::ClosePackageClassification` — derives `readiness` (passthrough of `Teller::Queries::EodReadiness`), `blockers`, `warnings`, and primary-only **`buckets`** (`posted`, `pending`, `reversed`, `held`, `overridden`, `exception`) without persisting classification rows. `EodReadiness` remains the only authority for `eod_ready` and close blockers.
- **Ops UI:** `GET /ops/close_package` ([`Ops::ClosePackagesController`](../../app/controllers/ops/close_packages_controller.rb)) is the canonical EOD workspace: readiness, blockers/warnings, classified summaries, trial balance, projection health when reviewing the current open day, embedded guarded **`POST /ops/business_date_close`**, and redirects back to Close package on success and failure ([`Ops::BusinessDateClosesController`](../../app/controllers/ops/business_date_closes_controller.rb)).
- **Presentation contract:** Summary operational-event buckets use **primary classification only** (e.g. `overdraft.nsf_denied` counts under **`exception`**, not **`posted`**); raw status/channel/event-type breakdowns on the same page retain full observability for support.
- **Legacy routes:** `GET /ops/eod` and `GET /ops/business_date_close` remain; dashboard copy points operators at Close package first.

---

## 9. References

- [ADR-0002](0002-operational-event-model.md)
- [ADR-0013](0013-holds-available-and-servicing-events.md)
- [ADR-0016](0016-trial-balance-and-eod-readiness.md)
- [ADR-0018](0018-business-date-close-and-posting-invariant.md)
- [ADR-0019](0019-event-catalog-and-fee-events.md)
- [ADR-0031](0031-cash-inventory-and-management.md)
- [ADR-0037](0037-internal-staff-authorized-surfaces.md)
- [ADR-0039](0039-teller-session-drawer-custody-projection.md)
- [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md)
