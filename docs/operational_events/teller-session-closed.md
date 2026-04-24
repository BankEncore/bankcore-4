# Teller session closed (`teller_session.closed`)

## Summary

Records that a teller drawer session **closed**: cash counts captured, **expected vs actual** compared, variance computed, and EOD discipline can require **all sessions closed** before branch day is considered complete.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `teller_session.closed` |
| **Category** | Operational (ADR-0002 §5.3) |
| **Phase** | Phase 1 (spec). |

## Semantics

- **Authoritative state** for MVP lives on **`teller_sessions`**, not only on this optional OE: **`CloseSession`** / **`ApproveSessionVariance`** ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)) set **`open`**, **`pending_supervisor`** (material variance over configured threshold), or **`closed`** with **`closed_at`**, expected/actual cash, **`variance_minor_units`**, and when applicable **`supervisor_approved_at`** / **`supervisor_operator_id`**.
- **Material variance** uses **`config.x.teller.variance_threshold_minor_units`** (env **`TELLER_VARIANCE_THRESHOLD_MINOR_UNITS`**); above threshold the session stays **not closed** until **`POST /teller/teller_sessions/approve_variance`** with a **supervisor** ([ADR-0015](../adr/0015-teller-workspace-authentication.md)). Separate **`override.approved`** OEs remain optional workflow glue.
- **Cash shortage/over** as an economic correction can be posted to GL via **`teller.drawer.variance.posted`** when ADR-0020 is enabled; otherwise session close stays **control state** only.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `teller_session.closed`. |
| `status` | Yes | Often `posted` when close succeeds; or `pending` while awaiting supervisor for variance. |
| `business_date` | Yes | |
| `channel` | Yes | |
| `idempotency_key` | Recommended | One close per session attempt. |
| Session reference | Yes | FK to `teller_sessions` (or embed session id in metadata). |

## Lifecycle

- **Table-first (implemented):** if variance is within threshold → **`teller_sessions.status = closed`** and **`closed_at`** set on close. If over threshold → **`pending_supervisor`** until supervisor approve → then **`closed`** with **`supervisor_approved_at`** set.
- **If this OE row exists:** mirror the same story with **`pending` → `posted`** on the event row, or keep the OE as future-only while the table remains source of truth.

## Posting

- **No** for the close event itself in MVP.
- **Optional (product flag):** **`teller.drawer.variance.posted`** is created from **`CloseSession`** / **`ApproveSessionVariance`** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is enabled ([ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)); see [teller-drawer-variance-posted.md](teller-drawer-variance-posted.md).

## Idempotency

- One successful close per session; replays return stable session state.

## Reversals

- Not a GL reversal pattern. Reopening a day may be a new operational story—defer.

## Relationships

- **`teller_sessions`:** authoritative close timestamps and counts.
- Links from **cash** operational events during the session via `teller_session_id`.

## Module ownership

- **`Teller`** (session close command); optional audit row in `operational_events` under `Core::OperationalEvents`.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §5.3
- [ADR-0014](../adr/0014-teller-sessions-and-control-events.md) — session close, variance threshold, approve command
- [ADR-0015](../adr/0015-teller-workspace-authentication.md) — supervisor gate on approve_variance
- [roadmap.md](../roadmap.md) — Phase 1 EOD / session closure

## Examples

```json
{
  "event_type": "teller_session.closed",
  "channel": "teller",
  "idempotency_key": "session-close-7-2026-04-22",
  "teller_session_id": 7
}
```

**Effect sketch:** Session 7 → `closed`, actual vs expected stored; if variance over threshold, supervisor approval recorded before `posted`.
