# ADR-0021: Interest accrual and payout first slice

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0003](0003-posting-journal-architecture.md), [ADR-0008](0008-money-currency-rounding-policy.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md)

---

## 1. Context

Phase 3 introduces deposit interest without the full product-rate engine. The first slice needs to prove the accounting path for deposit interest while keeping all posted money in the existing financial kernel: `operational_events`, `PostEvent`, posting rules, and journal lines.

The COA already includes **5100** Interest Expense - Deposits, **2510** Accrued Interest Payable - Deposits, and **2110** Noninterest-Bearing Demand Deposits. This slice uses those accounts directly and does not add product interest profile resolution.

---

## 2. Decision

Ship two explicit **`system`** channel financial event types:

| Event | Meaning | Posting |
| ----- | ------- | ------- |
| `interest.accrued` | Ledger-recognized deposit interest expense and payable, already rounded to currency minor units. | Dr **5100** / Cr **2510** (`deposit_account_id` on the 2510 leg). |
| `interest.posted` | Full payout of a posted `interest.accrued` into the customer DDA. | Dr **2510** / Cr **2110** (`deposit_account_id` on both legs). |

Both events use `Core::OperationalEvents::Commands::RecordEvent` and `Core::Posting::Commands::PostEvent`. Amounts are explicit **`amount_minor_units`** supplied by a system caller; this slice does not calculate interest.

`interest.posted` requires **`reference_id`** equal to the numeric id of a **posted** `interest.accrued` event with the same `source_account_id`, `amount_minor_units`, and `currency`. Only one posted payout may reference a given accrual.

---

## 3. Precision and rounding

`operational_events.amount_minor_units` and `journal_lines.amount_minor_units` remain integer currency minor units. `interest.accrued` records the **posting boundary amount**, not raw daily or intra-period computational accrual.

Future interest engines may accumulate sub-minor precision outside the ledger, for example `amount_micro_minor_units` / `amount_subminor_units` with a fixed scale such as **1 minor unit = 1,000,000 micro-minor units**, or with an explicit scale column. At the posting boundary, the engine emits rounded `amount_minor_units` and retains any residual sub-minor remainder in the accumulator.

Fractional cents must never enter `journal_lines`.

---

## 4. Reversal policy

Both event types are reversible by `posting.reversal`, subject to one guard:

- `interest.posted` can be reversed normally.
- `interest.accrued` cannot be reversed while a posted `interest.posted` references it. Follow-on adjustment policy for fully unwinding both events is outside this slice.

This preserves the payable settlement chain and avoids reversing expense/payable after the payable has already been paid into DDA.

---

## 5. Non-goals

- Rate tiers, day-count conventions, compounding, or balance averaging.
- Sub-minor / microcent accumulator tables.
- Partial payout of a single accrual.
- Product `InterestRuleResolver` from [ADR-0005](0005-product-configuration-framework.md).
- Teller cash-session workflow or teller-entered interest.
- Switching this slice to **2120** NOW account liability; this DDA slice credits **2110**.

---

## 6. Worked example

```json
{
  "event_type": "interest.accrued",
  "channel": "system",
  "idempotency_key": "interest-accrual-2026-04-30-acct-42",
  "amount_minor_units": 123,
  "currency": "USD",
  "source_account_id": 42
}
```

Posting: Dr **5100** 123 / Cr **2510** 123 (`deposit_account_id = 42`).

```json
{
  "event_type": "interest.posted",
  "channel": "system",
  "idempotency_key": "interest-post-2026-04-30-acct-42",
  "amount_minor_units": 123,
  "currency": "USD",
  "source_account_id": 42,
  "reference_id": "1001"
}
```

Posting: Dr **2510** 123 (`deposit_account_id = 42`) / Cr **2110** 123 (`deposit_account_id = 42`).
