# Master transaction capability registry

**Status:** Draft  
**Companion to:** [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md) (bank-wide families F1–F17), [branch-operations-capability-map.md](branch-operations-capability-map.md)

This document maps **business capability codes** and **[303](../concepts/303-bank-transaction-capability-taxonomy.md) families (F1–F17)** to **shipped** `operational_events.event_type` strings, **allowed channels** (from code), **primary domain ownership**, record paths, posting posture, and specs.

---

## Governance

**Source of truth for `event_type` strings** is **`Core::OperationalEvents::EventCatalog`** in `app/domains/core/operational_events/event_catalog.rb` — see [ADR-0019](../adr/0019-event-catalog-and-fee-events.md). The catalog is **code-first** metadata for discovery and drift tests; it is **not** a parallel database truth layer for event identity.

This registry adds **interpretation**: **family (F1–F17)**, a stable **capability code** for planning/RBAC-adjacent conversations, **`allowed_channels`** (copied from the catalog entry; **ground truth** remains Ruby), and **`primary_domain_owner`** (which module owns the **write path / invariants** for the row or the command that creates it — not “only channel `teller`”).

When the catalog changes, update the corresponding **shipped** rows here in the same PR. Do not maintain a duplicate YAML registry ([ADR-0019](../adr/0019-event-catalog-and-fee-events.md)).

---

## Column reference

| Column | Meaning |
| --- | --- |
| **Capability code** | Stable planning label (not necessarily a `Workspace` capability key). |
| **Family** | F1–F17 from [303](../concepts/303-bank-transaction-capability-taxonomy.md). |
| **`event_type`** | Shipped string; must match catalog. |
| **`allowed_channels`** | From `EventCatalog` — channels permitted when **recording** this type (e.g. `teller`, `branch`, `batch`, `system`, `api`). |
| **Primary domain owner** | Module that owns the command / invariants for this fact. |
| **Record path** | Primary command or entry point. |
| **GL / notes** | Posting posture and custody/session notes. |

---

## Shipped registry (EventCatalog)

| Capability code | Family | `event_type` | `allowed_channels` | Primary domain owner | Record path | GL / notes |
| --- | --- | --- | --- | --- | --- | --- |
| `DEPOSIT_ACCEPTED` | F1 | `deposit.accepted` | `teller`, `api`, `batch` | `Core::OperationalEvents` (+ `Accounts`, `Teller` session rules for cash) | `Core::OperationalEvents::Commands::RecordEvent` | Posts Dr `1110` / Cr `2110`; drawer projection when session-linked cash ([ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)) |
| `ACH_CREDIT_RECEIVED` | F6 | `ach.credit.received` | `batch` | `Integration::Ach` | `Integration::Ach::Commands::IngestReceiptFile` | Posts Dr `1120` / Cr `2110` ([ADR-0028](../adr/0028-ach-receipt-ingestion.md)) |
| `WITHDRAWAL_POSTED` | F1 | `withdrawal.posted` | `teller`, `api`, `batch` | `Core::OperationalEvents`, `Accounts` | `RecordEvent` + `Accounts::Commands::AuthorizeDebit` | Posts Dr `2110` / Cr `1110` |
| `TRANSFER_COMPLETED` | F1 | `transfer.completed` | `teller`, `api`, `batch` | `Core::OperationalEvents`, `Accounts` | `RecordEvent` + `AuthorizeDebit` | Posts across two `2110` legs |
| `POSTING_REVERSAL` | F5 | `posting.reversal` | `teller`, `branch`, `api`, `batch` | `Core::OperationalEvents`, `Core::Posting` | `Core::OperationalEvents::Commands::RecordReversal` | Compensating journal |
| `FEE_ASSESSED` | F1 / F3 | `fee.assessed` | `teller`, `api`, `batch`, `system` | `Core::OperationalEvents` (engine: `Deposits` / `Accounts`) | `RecordEvent` | Posts fee income pattern ([ADR-0019](../adr/0019-event-catalog-and-fee-events.md)) |
| `FEE_WAIVED` | F1 / F3 | `fee.waived` | `teller`, `branch`, `api`, `batch` | `Core::OperationalEvents`, `Core::Posting` | `RecordEvent` | Compensates posted `fee.assessed` |
| `INTEREST_ACCRUED` | F15 | `interest.accrued` | `system` | `Core::OperationalEvents`, `Deposits` | `RecordEvent` | Accrual posting ([ADR-0021](../adr/0021-interest-accrual-and-payout-slice.md)) |
| `INTEREST_POSTED` | F15 | `interest.posted` | `system` | `Core::OperationalEvents`, `Deposits` | `RecordEvent` | Links to accrued via `reference_id` |
| `TELLER_DRAWER_VARIANCE_POSTED` | F11 | `teller.drawer.variance.posted` | `system` | `Teller`, `Core::OperationalEvents` | `RecordEvent` (via session close / variance approval path) | Optional GL `1110` / `5190` ([ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)) |
| `CASH_VARIANCE_POSTED` | F4 | `cash.variance.posted` | `system` | `Cash`, `Core::Posting` | `Cash::Commands::ApproveCashVariance` | GL adjustment for approved location variance ([ADR-0031](../adr/0031-cash-inventory-and-management.md)) |
| `CASH_SHIPMENT_RECEIVED` | F4 | `cash.shipment.received` | `branch` | `Cash` | `Cash::Commands::ReceiveExternalCashShipment` | Dr `1110` / Cr `1130` ([ADR-0035](../adr/0035-external-cash-shipments.md)) |
| `CASH_MOVEMENT_COMPLETED` | F4 | `cash.movement.completed` | `teller`, `branch`, `system` | `Cash` | `Cash::Commands::TransferCash` | No GL for ordinary internal custody |
| `CASH_COUNT_RECORDED` | F4 | `cash.count.recorded` | `teller`, `branch`, `system` | `Cash` | `Cash::Commands::RecordCashCount` | No GL; may precede variance approval |
| `HOLD_PLACED` | F1 | `hold.placed` | `teller`, `branch`, `api`, `batch` | `Accounts` | `Accounts::Commands::PlaceHold` | No GL ([ADR-0013](../adr/0013-holds-available-and-servicing-events.md)) |
| `HOLD_RELEASED` | F1 | `hold.released` | `teller`, `branch`, `api`, `batch` | `Accounts` | `Accounts::Commands::ReleaseHold` | No GL |
| `OVERRIDE_REQUESTED` | F5 | `override.requested` | `teller`, `branch`, `batch` | `Core::OperationalEvents` | `Core::OperationalEvents::Commands::RecordControlEvent` | No GL |
| `OVERRIDE_APPROVED` | F5 | `override.approved` | `teller`, `branch`, `batch` | `Core::OperationalEvents` | `RecordControlEvent` | No GL |
| `OVERDRAFT_NSF_DENIED` | F5 | `overdraft.nsf_denied` | `teller`, `api`, `batch` | `Core::OperationalEvents`, `Accounts` | `RecordControlEvent` (debit denial path) | No GL; may link to NSF `fee.assessed` ([ADR-0023](../adr/0023-overdraft-nsf-deny-and-fee.md)) |
| `ACCOUNT_RESTRICTED` | F8 | `account.restricted` | `branch` | `Accounts` | `Accounts::Commands::RestrictAccount` | No GL ([ADR-0036](../adr/0036-branch-servicing-event-audit-taxonomy.md)) |
| `ACCOUNT_UNRESTRICTED` | F8 | `account.unrestricted` | `branch` | `Accounts` | `Accounts::Commands::UnrestrictAccount` | No GL |
| `ACCOUNT_CLOSED` | F8 | `account.closed` | `branch` | `Accounts` | `Accounts::Commands::CloseAccount` | No GL |

---

## Planned capabilities (no shipped `event_type` yet)

Use [303](../concepts/303-bank-transaction-capability-taxonomy.md) phased slices (**T1–T4**) and branch roadmap phases for sequencing. Rows below are **placeholders** — **`event_type` TBD** until an ADR names the catalog entry.

| Capability code (planned) | Family | `event_type` | Typical channels (planned) | Primary domain owner (planned) |
| --- | --- | --- | --- | --- |
| Check deposit / item acceptance | F2 | TBD | `teller`, `branch` | `Integration` / future `Instruments` — ADR required |
| Official check issuance | F2 | TBD | `teller`, `branch` | Future `Instruments` — ADR required |
| Miscellaneous GL / non-DDA receipt | F3 | TBD | `branch`, `batch` | `Core::Ledger` + controlled Ops surface — ADR required |

---

## References

| Document | Role |
| --- | --- |
| [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md) | Bank-wide capability families F1–F17 |
| [302-teller-transaction-surface.md](../concepts/302-teller-transaction-surface.md) | Teller-adjacent execution surface |
| [ADR-0019](../adr/0019-event-catalog-and-fee-events.md) | Event catalog SSOT |
| `app/domains/core/operational_events/event_catalog.rb` | **`allowed_channels`** and metadata |
