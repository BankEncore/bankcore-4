# Fee assessed (`fee.assessed`)

## Summary

Records a **deposit service charge** assessed to a demand deposit account (`source_account_id`). Posting reduces customer DDA liability (GL **2110**) and recognizes **deposit service charge income** (GL **4510**).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `fee.assessed` |
| **Category** | Financial |
| **Phase** | Implemented ([ADR-0019](../adr/0019-event-catalog-and-fee-events.md)). |

## Semantics

- **Must** reference an **open** `deposit_accounts` row via `source_account_id`.
- **Must** carry a positive `amount_minor_units` and `currency` (MVP: USD).
- **Available balance:** must be sufficient (same projection as `withdrawal.posted` per [ADR-0004](../adr/0004-account-balance-model.md)).
- **Not** a teller-cash drawer movement: **`teller_session_id`** is **not** required for `channel: teller` when the cash session gate is on.
- P3-3 monthly maintenance engine creates this same event with **`channel: "system"`**; no separate event type is used for engine-origin fees.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `reference_id` | No | Manual fees leave this blank. Engine-created monthly maintenance fees use `monthly_maintenance:<rule_id>:<business_date>` ([ADR-0022](../adr/0022-monthly-maintenance-fee-engine.md)). |

## Lifecycle

`pending` → `posted` via `PostEvent` (same pattern as other financial events).

## Posting

| Leg | GL | Side | `deposit_account_id` |
| --- | --- | --- | --- |
| 1 | 2110 | debit | `source_account_id` |
| 2 | 4510 | credit | nil |

## Idempotency

Fingerprint: `event_type`, `channel`, `idempotency_key`, `amount_minor_units`, `currency`, `source_account_id`; includes **`reference_id`** when present for engine-created fees.

## Reversals

**Not** reversible via `posting.reversal`. Use **`fee.waived`** referencing the posted `fee.assessed` event id in `reference_id` ([ADR-0019](../adr/0019-event-catalog-and-fee-events.md)).

## Module ownership

`Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::PostingRules::FeeAssessed`.

## References

- [ADR-0019](../adr/0019-event-catalog-and-fee-events.md)
- [ADR-0012](../adr/0012-posting-rule-registry-and-journal-subledger.md)
- [ADR-0022](../adr/0022-monthly-maintenance-fee-engine.md)
