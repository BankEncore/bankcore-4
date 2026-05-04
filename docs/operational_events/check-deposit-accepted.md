# Check deposit accepted (`check.deposit.accepted`)

## Summary

Records that the institution **accepted** a **check deposit** ticket against an open DDA: structured **items** (identity + amounts), immediate **GL posting** (clearing asset debit, liability credit), optional **event-level hold** at acceptance via **`AcceptCheckDeposit`**. No teller drawer / expected-cash delta for this event type (ADR-0040).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `check.deposit.accepted` |
| **Category** | Financial |
| **Phase** | T1 slice ([ADR-0040](../adr/0040-check-deposit-vertical-slice.md)). |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `teller` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/check-deposit-accepted.md` |
| **Support search keys** | `source_account_id`, `actor_id`, `teller_session_id`, `idempotency_key` |

## Semantics

- **Catalog channels:** widening beyond **`teller`** requires the concrete producer, matching `EventCatalog` / README / capability registry / tests in the same change.
- **Must** use **`channel: teller`** when recording via `RecordEvent` validation rules for this type.
- **Must** reference an **open** `deposit_accounts` row via `source_account_id`.
- **Does not require** an open `TellerSession`; `teller_session_id` is optional audit/trace only.
- **Held-at-acceptance** flows **must** use **`AcceptCheckDeposit`** (single transaction: record → post → optional `PlaceHold`) — do not sequence separate HTTP record/post/hold for that intent.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | Literal `check.deposit.accepted`. |
| `payload` | Yes | Canonical JSONB `{ "items" => [...] }` after validation (normalized only). |
| `status` | Yes | `pending` until posting; then `posted`. |
| `amount_minor_units` | Yes | Header total; **must equal** sum of item amounts. |
| `currency` | Yes | MVP: USD. |
| `source_account_id` | Yes | Account credited (`2110` subledger). |
| `teller_session_id` | Optional | Not used for cash session gate or drawer projection. |

### Payload items (T1)

Each item:

- `amount_minor_units` (positive integer)
- **Exactly one** of `item_reference` or `serial_number` (non-blank string after strip)
- Optional `classification`: `on_us`, `transit`, or `unknown` only when present
- **No other keys** at item or payload root (root allows only `items`).

Limits: max **100** items; serialized canonical JSON max **65536** bytes.

## Lifecycle

1. **`pending`** — Inserted by `RecordEvent`.
2. **`posted`** — `PostEvent` applies Dr **`1160`** / Cr **`2110`**.

## Posting

- **Debit** GL **1160** (Deposited Items Clearing); **credit** GL **2110** with `deposit_account_id` on the credit leg.

## Idempotency

- **Scope:** `(channel, idempotency_key)` unique.
- **Fingerprint** includes canonical payload digest (`check_deposit_digest`), `teller_session_id`, and standard financial scalars — see [`RecordEvent`](../../app/domains/core/operational_events/commands/record_event.rb).

## Reversals

- Reversible via **`posting.reversal`** like other posted financial events.
- **Blocked** while **active** holds reference `placed_for_operational_event_id` = this event.

## Read surfaces

| Surface | Policy |
| --- | --- |
| Detail | Full normalized **`payload`** (`items`). |
| List / search / receipts | **`payload_summary`** only (`items_count`, totals, masked identities) — no full `items` array. |

## Module ownership

- **Orchestration / validate:** `Core::OperationalEvents::Commands::AcceptCheckDeposit`, `RecordEvent`, `Services::CheckDepositPayload`.
- **Post:** `Core::Posting` (`PostingRules::CheckDepositAccepted`).

## References

- [ADR-0040](../adr/0040-check-deposit-vertical-slice.md)
- [ADR-0013](../adr/0013-holds-available-and-servicing-events.md)
- [ADR-0019](../adr/0019-event-catalog-and-fee-events.md)

## Examples

Minimal teller JSON (orchestration entry via `POST /teller/operational_events`):

```json
{
  "operational_event": {
    "event_type": "check.deposit.accepted",
    "channel": "teller",
    "idempotency_key": "chk-001",
    "amount_minor_units": 5000,
    "currency": "USD",
    "source_account_id": 42,
    "payload": {
      "items": [
        { "amount_minor_units": 3000, "item_reference": "CHK-A", "classification": "on_us" },
        { "amount_minor_units": 2000, "serial_number": "987654321" }
      ]
    },
    "hold_amount_minor_units": 5000,
    "hold_idempotency_key": "chk-001-hold"
  }
}
```

Posting snapshot: Dr **1160** 5000 / Cr **2110** 5000 (`deposit_account_id` = source account).
