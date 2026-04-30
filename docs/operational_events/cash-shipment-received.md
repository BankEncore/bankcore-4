# cash.shipment.received

## Summary

Records that an external cash shipment from the Federal Reserve or a correspondent bank has been received into an active branch vault.

## Registry

| Field | Value |
| ----- | ----- |
| **event_type** | `cash.shipment.received` |
| **Category** | `financial` |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `branch` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/cash-shipment-received.md` |
| **Support search keys** | `reference_id`, `actor_id`, `idempotency_key` |

## Semantics

`reference_id` is the numeric id of a completed `cash_movements` row with movement type `external_shipment_received`. The movement stores the destination vault, external source, shipment reference, actor, business date, and operating unit.

## Persistence

The event stores `amount_minor_units`, `currency`, `actor_id`, `operating_unit_id`, and `reference_id`.

## Lifecycle

The receipt command creates the movement, projects the vault balance, records a pending event through `RecordEvent`, posts it through `Core::Posting::Commands::PostEvent`, and links the movement to the posted event in one transaction.

## Posting

Dr `1110` Cash in Vaults; Cr `1130` Due from Correspondent Banks.

## Idempotency

The command-level key is supplied by the caller. Replay must match destination vault, amount, currency, business date, source, shipment reference, and actor. Matching replay returns the original movement and does not create another event, projection, or journal entry.

## Reversals

Reversible through `posting.reversal` for GL correction. The reversal does not automatically change Cash-domain custody balances; physical custody corrections remain Cash-domain activity.

## Module ownership

`Cash` owns the receipt command, movement row, and custody balance projection. `Core::OperationalEvents` owns event validation, and `Core::Posting` owns journal generation.

## References

[ADR-0035](../adr/0035-external-cash-shipments.md)

## Examples

```json
{
  "event_type": "cash.shipment.received",
  "channel": "branch",
  "reference_id": "42",
  "amount_minor_units": 5000000,
  "currency": "USD"
}
```
