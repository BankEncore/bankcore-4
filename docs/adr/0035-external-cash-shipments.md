# ADR-0035: External Cash Shipment Receipts

## Status

Accepted

## Context

ADR-0031 established the Cash domain as the owner of physical cash custody and deferred Fed/correspondent shipment accounting until a COA mapping was explicit. Internal vault, drawer, and transit movements stay within aggregate GL `1110` and do not post journal entries. Receiving physical cash from an external counterparty is different: institutional cash under custody increases and the external settlement or due-from asset decreases.

The seeded chart of accounts already defines:

- `1110` Cash in Vaults (physical cash under branch custody)
- `1120` ACH Settlement (reserved for ACH receipt flows)
- `1130` Due from Correspondent Banks (nostro/correspondent balances)

`1120` must remain ACH-specific. For this slice, external cash shipments from the Federal Reserve or correspondent banks settle against `1130`.

## Decision

BankCORE will implement `Cash::Commands::ReceiveExternalCashShipment` as a single-step receipt command for cash that has already arrived at an active branch vault.

The command will:

- Create a completed `cash_movements` row with movement type `external_shipment_received`.
- Require a destination branch vault, positive USD amount, actor, operating unit, source name, shipment reference, business date, and idempotency key.
- Increase the destination vault cash balance through the Cash balance projector.
- Record and immediately post `cash.shipment.received` through `Core::OperationalEvents` and `Core::Posting`.

Posting pattern:

```text
Dr 1110 Cash in Vaults
Cr 1130 Due from Correspondent Banks
```

`reference_id` on the operational event is the numeric `cash_movements.id`. The movement stores the external source and shipment reference for support evidence.

## Controls

- `cash.shipment.receive` gates branch receipt entry.
- Receipts are append-oriented; edits are not allowed after posting.
- The idempotency key is unique on `cash_movements`. A replay with the same material fields returns the original movement and must not re-project cash or re-post GL.
- A replay with different material fields is rejected.
- The command must run only for the current open business date.

## Reversals

`cash.shipment.received` is reversible through the existing `posting.reversal` mechanism for GL correction. Reversing GL does not automatically unwind Cash-domain custody. Operational custody corrections should be made with a later Cash-domain count and approved variance, or a future explicit external shipment correction workflow.

## Deferred

This ADR does not add outbound shipment dispatch, shipment requests, carrier manifests, in-transit states, partial receipts, over/short shipment exceptions, or settlement matching. Those workflows can introduce a dedicated `cash_shipments` table when lifecycle state becomes first-class.
