# cash.variance.posted

## Summary

Records the GL adjustment for an approved Cash-domain custody variance. It is created by Cash approval workflow, not by teller-session close.

## Registry

| Field | Value |
| ----- | ----- |
| **event_type** | `cash.variance.posted` |
| **Category** | `financial` |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `system` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/cash-variance-posted.md` |
| **Support search keys** | `reference_id`, `actor_id` |

## Semantics

`reference_id` is the numeric id of an approved `cash_variance`. The signed amount must match `cash_variances.amount_minor_units`; negative is a shortage and positive is an overage.

## Persistence

The event stores `amount_minor_units`, `currency`, `actor_id`, `operating_unit_id`, and `reference_id`.

## Lifecycle

The row starts `pending` through `RecordEvent` and becomes `posted` through `Core::Posting::Commands::PostEvent`.

## Posting

Shortage: Dr `5190`, Cr `1110`. Overage: Dr `1110`, Cr `5190`.

## Idempotency

The deterministic key is `cash-variance-posted:<cash_variance_id>`. Replay must match signed amount, currency, reference id, and operating unit.

## Reversals

Not reversible via `posting.reversal` in this slice. Corrections are handled by a new count and approved variance.

## Relationships

Links to `cash_variances` through `reference_id`; the variance stores `cash_variance_posted_event_id`.

## Module ownership

`Cash` owns approval and variance rows. `Core::OperationalEvents` owns event validation, and `Core::Posting` owns GL legs.

## References

[ADR-0031](../adr/0031-cash-inventory-and-management.md)

## Examples

```json
{
  "event_type": "cash.variance.posted",
  "channel": "system",
  "reference_id": "42",
  "amount_minor_units": -500,
  "currency": "USD"
}
```
