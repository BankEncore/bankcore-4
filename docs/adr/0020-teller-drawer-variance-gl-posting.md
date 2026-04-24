# ADR-0020: Optional GL posting for teller drawer cash variance

**Status:** Accepted  
**Date:** 2026-04-22  
**Aligns with:** [ADR-0014](0014-teller-sessions-and-control-events.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0002](0002-operational-event-model.md), [ADR-0010](0010-ledger-persistence-and-seeded-coa.md)

---

## 1. Context

[ADR-0014](0014-teller-sessions-and-control-events.md) records **drawer cash variance** on `teller_sessions` (`variance_minor_units = actual - expected`) and supervisor approval for material variance, but defers **GL cash adjustment** to a future financial `event_type`. Institutions that want the **vault cash asset (1110)** to reflect drawer counts without a separate manual journal need an automated, auditable path aligned with [ADR-0002](0002-operational-event-model.md).

---

## 2. Decision

1. **Optional product branch** — Posting is **off by default**. Enable with **`Rails.application.config.x.teller.post_drawer_variance_to_gl`**, set from env **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** (truthy when not `false` / `0` / `no`, same pattern as [ADR-0014](0014-teller-sessions-and-control-events.md) cash-session flag). When disabled, behavior matches ADR-0014 (no new operational events from session close).

2. **Financial event** — Introduce **`teller.drawer.variance.posted`**: a **`RecordEvent`** financial row with **`channel: system`**, **`teller_session_id`** set, **`source_account_id` null** (no DDA leg), **`amount_minor_units` signed** and equal to **`teller_sessions.variance_minor_units`** at close time (negative = shortage, positive = overage). **Idempotency:** `(channel, idempotency_key)` with deterministic key **`drawer-variance-{teller_session_id}`** so retries and duplicate supervisor approve cannot create a second row.

3. **Trigger (MVP option A)** — Post **once** when the session first reaches **`closed`** with **non-zero** variance:
   - **Within threshold:** `CloseSession` closes immediately → record + post in the same DB transaction as the session update.
   - **Over threshold:** `ApproveSessionVariance` moves **`pending_supervisor` → `closed`** → record + post in that transaction.
   - **Zero variance:** no operational event.

   Option **B** (GL only after supervisor approval, ignoring in-threshold non-zero variance) is **not** implemented; it remains a product fork if needed later.

4. **Channel restriction** — **`teller.drawer.variance.posted` is only accepted on `channel: system`**. Teller HTTP must not create this type directly; orchestration lives in **`Teller::Services::PostDrawerVarianceToGl`** invoked from **`CloseSession`** / **`ApproveSessionVariance`**.

5. **Posting template (MVP)** — Magnitude **`abs(amount_minor_units)`**; GL **1110** (Cash in Vaults) and **5190** (Teller Cash Over and Short — expense, natural debit per [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) seed):
   - **Shortage** (amount &lt; 0): Dr **5190** / Cr **1110**.
   - **Overage** (amount &gt; 0): Dr **1110** / Cr **5190**.  
   No `deposit_account_id` on lines (no DDA subledger).

6. **Catalog** — `Core::OperationalEvents::EventCatalog` documents metadata; it is **not** a second persistence truth for `event_type` (same rule as [ADR-0019](0019-event-catalog-and-fee-events.md)).

7. **Reversals** — **`teller.drawer.variance.posted` is not** in **`RecordReversal::REVERSIBLE_TYPES`**. Corrections are **out of scope** for this ADR (manual adjustment or a future compensating event).

---

## 3. Consequences

- Trial balance and EOD flows see **1110** / **5190** movement when the flag is on and variance is non-zero.
- Session close / approve commands gain a **hard dependency** on `Core::OperationalEvents` + `Core::Posting` when the flag is enabled; failures roll back with the enclosing session transaction.
- Operators may see **`teller.drawer.variance.posted`** in **`GET /teller/operational_events`** with **`source_account_id` null**; list queries already treat source as optional.

---

## 4. References

- [ADR-0014](0014-teller-sessions-and-control-events.md) — variance workflow (updated cross-link).
- [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md) — registry row for this type.
- [docs/operational_events/teller-drawer-variance-posted.md](../operational_events/teller-drawer-variance-posted.md) — per-type spec.
