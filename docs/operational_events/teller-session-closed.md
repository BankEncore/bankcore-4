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

- **Does not** replace the **`teller_sessions`** row state; the session table typically holds `closed_at`, expected/actual cash in minor units, variance.
- **Material variance** may require **supervisor approval** before the close is accepted (link to `override.approved` or supervisor fields on session—implementation choice).
- **Cash shortage/over** as an economic correction may later be a **separate financial** `event_type` if posted to GL; keep session **close** as control state, not mixed with adjustment posting unless ADR says otherwise.

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

- If supervisor required: **`pending`** until approved, then **`posted`**.
- If no variance gate: **`posted`** immediately with session row updated atomically.

## Posting

- **No** for the close event itself in MVP.
- **Future:** separate `cash.adjustment` (or similar) **financial** event if variance hits GL.

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
