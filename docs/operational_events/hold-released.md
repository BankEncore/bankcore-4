# Hold released (`hold.released`)

## Summary

Records that a previously **active** hold against a deposit account was **released** (operator action or policy), restoring **available** balance without changing posted **ledger** balance (ADR-0004).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `hold.released` |
| **Category** | Servicing (ADR-0002 §5.2) |
| **Phase** | Phase 1 (spec). |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `teller`, `branch`, `api`, `batch` |
| **Financial impact** | `no_gl` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/hold-released.md` |
| **Support search keys** | `source_account_id`, `reference_id`, `actor_id` |

## Semantics

- **Must** reference an existing hold (typically by id in payload / `reference_id` when persisted) that was **`active`**.
- After success, that hold is **`released`** (or equivalent terminal state); available increases by the released amount.
- Does **not** delete the original `hold.placed` event or hold history row.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `hold.released`. |
| `status` | Yes | `pending` → `posted` when release is durable (Option A) or single-step `posted`. |
| `channel`, `idempotency_key` | Yes | For retriable APIs. |
| `source_account_id` | Yes | Account whose hold is released (consistency check vs hold row). |
| Hold reference | Yes | FK to `holds` or stable identifier in metadata / `reference_id` when column exists. |
| `amount_minor_units` | Optional | If partial release is supported later; MVP may be full release only (amount implied by hold). |

## Lifecycle

Same servicing pattern as [hold-placed.md](hold-placed.md): no GL posting; **`posted`** means business state committed.

## Posting

- **No** (typical MVP).

## Idempotency

- Fingerprint includes hold identifier and account; replays return same outcome without double-applying release.

## Reversals

- Releasing a hold is not a “reversal” in the ADR-0002 §6 GL sense; do not use compensating journals for standard release.

## Relationships

- **Pairs with** `hold.placed` and the **`holds`** row being updated.

## Module ownership

- Same as holds placement; **`Accounts`** or **`Core::OperationalEvents`** per chosen ADR.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §5.2
- [ADR-0004](../adr/0004-account-balance-model.md) §6.4

## Examples

```json
{
  "event_type": "hold.released",
  "channel": "teller",
  "idempotency_key": "hold-rel-2026-04-22-001",
  "source_account_id": 42,
  "hold_id": 9001
}
```

**Effect sketch:** Hold 9001 → `released`; available increases accordingly.
