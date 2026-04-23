# ADR-0014: Teller sessions and control operational events (MVP)

**Status:** Accepted  
**Date:** 2026-04-23  
**Aligns with:** [roadmap.md](../roadmap.md) Phase 1, [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Decision

- **`teller_sessions`** is owned by **`Teller`**. Lifecycle: **`Teller::Commands::OpenSession`** / **`CloseSession`**. MVP uses **table-first** audit; optional `teller_session.opened` / `closed` operational event rows are **not** required for this slice.
- **`operational_events.teller_session_id`** optionally links financial events to a session when clients pass it.
- **`override.requested`** / **`override.approved`** are recorded via **`Core::OperationalEvents::Commands::RecordControlEvent`** (posted immediately, no GL). **`reference_id`** carries the subject (e.g. `teller_session:123`). Variance/supervisor workflow wiring is deferred beyond storing the audit row.

---

## 2. API

Teller JSON routes are listed in [docs/operational_events/README.md](../operational_events/README.md).
