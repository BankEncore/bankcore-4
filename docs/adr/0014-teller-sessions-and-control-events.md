# ADR-0014: Teller sessions and control operational events (MVP)

**Status:** Accepted  
**Date:** 2026-04-23  
**Aligns with:** [roadmap.md](../roadmap.md) Phase 1, [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Decision

- **`teller_sessions`** is owned by **`Teller`**. Lifecycle: **`Teller::Commands::OpenSession`** / **`CloseSession`** / **`ApproveSessionVariance`**. MVP uses **table-first** audit; optional `teller_session.opened` / `closed` operational event rows are **not** required for this slice.
- **`operational_events.teller_session_id`** optionally links financial events to a session when clients pass it.
- **`override.requested`** / **`override.approved`** are recorded via **`Core::OperationalEvents::Commands::RecordControlEvent`** (posted immediately, no GL). **`reference_id`** carries the subject (e.g. `teller_session:123`). Manual override OEs remain optional alongside session state.
- **Cash variance on close:** `CloseSession` compares **`abs(actual_cash_minor_units - expected_cash_minor_units)`** to **`Rails.application.config.x.teller.variance_threshold_minor_units`** (default from env **`TELLER_VARIANCE_THRESHOLD_MINOR_UNITS`**, integer minor units; default **0** so any non-zero variance requires supervisor). If **strictly greater** than the threshold, the session moves to **`pending_supervisor`**, variance fields are stored, and **`closed_at`** / **`supervisor_approved_at`** stay **nil** until a supervisor approves. Otherwise the session is **`closed`** immediately with **`closed_at`** set.
- **Supervisor approval:** **`Teller::Commands::ApproveSessionVariance`** transitions **`pending_supervisor` → `closed`**, sets **`closed_at`**, **`supervisor_approved_at`**, and **`supervisor_operator_id`** (FK → **`operators`**) when supplied. Duplicate approve after a successful variance approval is **idempotent** (returns the same closed session). Approving a session that was never **`pending_supervisor`** is rejected (**invalid state**).
- **GL cash adjustment** for drawer variance was **out of scope** for the original MVP table-first session slice; when product enables it, **`teller.drawer.variance.posted`** is recorded and posted per [ADR-0020](0020-teller-drawer-variance-gl-posting.md) (`TELLER_POST_DRAWER_VARIANCE_TO_GL`).
- **Open session for teller cash:** When **`Rails.application.config.x.teller.require_open_session_for_cash`** is **true** (default from env **`TELLER_REQUIRE_OPEN_SESSION_FOR_CASH`**, same truthy/falsey pattern as other teller env flags), **`RecordEvent`** rejects **`deposit.accepted`** and **`withdrawal.posted`** on **`channel: teller`** unless **`teller_session_id`** references an **`open`** `teller_sessions` row. **`transfer.completed`** on teller channel is **exempt**. Idempotency **fingerprints** for those gated types **include `teller_session_id`** so replays cannot swap sessions under the same idempotency key.

---

## 2. API

Teller workspace routes (including **`GET /teller/reports/*`** per [ADR-0016](0016-trial-balance-and-eod-readiness.md)) are listed in [docs/operational_events/README.md](../operational_events/README.md). **Authentication and supervisor gates** for the teller workspace (`X-Operator-Id`, reversal / `override.approved`, **`POST /teller/teller_sessions/approve_variance`**) are defined in [ADR-0015](0015-teller-workspace-authentication.md).

**Approve variance body (JSON):** `{ "teller_session_approve_variance": { "teller_session_id": <id> } }` with supervisor **`X-Operator-Id`**.
