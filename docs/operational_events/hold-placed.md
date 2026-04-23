# Hold placed (`hold.placed`)

## Summary

Records that an **active hold** was applied against a deposit account so **available** balance drops while **ledger** balance (posted journal total) is unchanged (ADR-0004).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `hold.placed` |
| **Category** | Servicing (ADR-0002 §5.2) |
| **Phase** | Phase 1 (spec; `holds` table ownership to confirm in implementation ADR). |

## Semantics

- Reduces **authorization / available** funds; does **not** by itself post GL lines in the typical model.
- **Must** reference the deposit account and hold amount; hold lifecycle (active → released/expired) lives primarily on the **`holds`** row if present.
- This operational event row is the **audit anchor** for “why was available reduced?” and can correlate to `source_operational_event_id` on the hold row (implementation choice).

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `hold.placed`. |
| `status` | Yes | See **Lifecycle** — define whether `posted` means “hold row committed” or align with a future convention. |
| `business_date`, `channel`, `idempotency_key` | Yes | If external retries exist. |
| `amount_minor_units` | Yes | Hold amount. |
| `currency` | Yes | |
| `source_account_id` | Yes | Account under hold (deposit account). |
| **`holds` table** | Recommended | Columns per ADR-0004 §6: account, amount, status, timestamps, reason, optional link to this event id. |

## Lifecycle

**Option A (recommended for clarity):** `hold.placed` moves to **`posted`** when the `holds` row is persisted in **`active`** status in the same transaction as the event row.

**Option B:** Servicing events use only `posted` without `pending` if there is no async step—document in implementation.

**Must not** imply GL posting unless product explicitly adds a GL-backed hold model (out of MVP scope here).

## Posting

- **No** GL journal in the standard ADR-0004 model for holds.

## Idempotency

- Fingerprint includes account, amount, currency, and any fields that distinguish two legitimate distinct holds (e.g. reason code when added).

## Reversals

- **Not** “reversed” by editing this row. Release is **`hold.released`** (or expiry path) which restores available without changing historical `hold.placed` rows.

## Relationships

- **`source_account_id`:** account whose **available** is reduced.
- Link to **`holds.id`** via FK on hold row pointing to this event, or `reference_id` when column exists.

## Module ownership

- **`holds` table:** commonly **`Accounts`** or **`Core::OperationalEvents`** — pick one owner and document in ADR; commands should stay out of `Teller` for hold math.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §5.2
- [ADR-0004](../adr/0004-account-balance-model.md) §5–6

## Examples

```json
{
  "event_type": "hold.placed",
  "channel": "teller",
  "idempotency_key": "hold-2026-04-22-001",
  "amount_minor_units": 2000,
  "currency": "USD",
  "source_account_id": 42
}
```

**Effect sketch:** `holds` row `active` for 2_000 on account 42; available for authorization decreases by 2_000; no new journal lines.
