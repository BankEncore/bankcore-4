# Teller session opened (`teller_session.opened`)

## Summary

Records that a **teller drawer session** (or equivalent cash accountability session) **opened** for business: the starting point for correlating cash-affecting operational events and EOD checks (Phase 1).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `teller_session.opened` |
| **Category** | Operational (ADR-0002 §5.3) |
| **Phase** | Phase 1 (spec; may coexist with `teller_sessions` table as source of truth). |

## Semantics

- **Does not** by itself move customer GL balances in MVP.
- Establishes **audit evidence** that a session started (who, when, which drawer/branch).
- **At most one open session** per teller/drawer (or per policy) should be enforced at the database or command layer—not necessarily via opaque `idempotency_key` alone.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `teller_session.opened`. |
| `status` | Yes | Often **`posted`** immediately if there is no async step; or `pending` if tied to supervisor approval (unusual for open). |
| `business_date` | Yes | |
| `channel` | Yes | Typically `teller`. |
| `idempotency_key` | Policy | May be less central than for money events; uniqueness of “open session” may use DB constraint on `teller_sessions`. |
| `amount_minor_units` | Optional | Opening float could be modeled here or only on `teller_sessions`; if unused, null. |
| **`teller_sessions` row** | Recommended | Holds `opened_at`, drawer/branch ids, expected counts—see Teller module catalog. |

## Lifecycle

Define explicitly whether this row is always **`posted`** on insert or uses **`pending`**. Prefer **single-step `posted`** when open is synchronous and session table holds detailed state.

## Posting

- **No** GL in MVP for session open itself.

## Idempotency

- Prefer **structural** uniqueness (one open session per drawer) over replaying the same idempotency key for different opens.

## Reversals

- **Not** GL-reversed. Closing a session is a separate event ([teller-session-closed.md](teller-session-closed.md)); erroneous open may be corrected by operational procedure or a future `session.voided` pattern—out of Phase 1 unless specified.

## Relationships

- Money events (`deposit.accepted`, `withdrawal.posted`, …) may carry **`teller_session_id`** pointing at the session opened here.

## Module ownership

- **`Teller`** module: `teller_sessions`, session commands; `Core::OperationalEvents` may only persist the audit row if you dual-write.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §5.3
- [bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md) — `Teller`, `Cash`

## Examples

```json
{
  "event_type": "teller_session.opened",
  "channel": "teller",
  "idempotency_key": "session-open-drawer-3-2026-04-22",
  "business_date": "2026-04-22"
}
```

**Note:** Drawer id and branch may live on `teller_sessions` or JSON metadata once columns exist. **Who opened the session** may later reference **`operators.id`** (same table as `operational_events.actor_id` per [ADR-0015](../adr/0015-teller-workspace-authentication.md)); table-first MVP may omit a dedicated OE row.
