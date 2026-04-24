# ADR-0024: Customer-visible history and statements

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [ADR-0004](0004-account-balance-model.md), [ADR-0005](0005-product-configuration-framework.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0013](0013-holds-available-and-servicing-events.md), [ADR-0023](0023-overdraft-nsf-deny-and-fee.md)

---

## 1. Context

Phase 3 needs customer-visible account history and statements without introducing a second balance ledger. ADR-0004 already requires booked balance to come from posted journals, while holds and servicing events remain clearly distinguished from ledger truth.

The first statement slice persists generated statement snapshots, but does not expose a customer HTTP surface or document delivery workflow.

---

## 2. Decision

Add product-owned statement profiles for deposit products. The first supported frequency is **monthly** with a configured `cycle_day` from **1** to **31**. When a month has fewer days than the configured cycle day, the cycle anchor clamps to the month end.

Add a new **`Deposits`** domain for statement-cycle orchestration and generated deposit statements. `Deposits` reads from `Accounts`, `Products`, `Core::OperationalEvents`, and `Core::Ledger`; it does not create financial events or journal lines.

Generated statements are immutable snapshots of the statement view for one account and period:

- opening and closing ledger balances
- debit and credit totals for ledger-affecting DDA activity
- JSON line items derived from posted journals and selected no-GL operational events

---

## 3. Balance and line rules

Statement ledger balances use the same DDA convention as available balance:

- GL account **2110**
- `journal_lines.deposit_account_id` equals the statement account
- signed line amount = credit amount minus debit amount

Operational events provide customer-facing context: event type, reference id, reversal linkage, channel, and source/destination account ids. Reversals appear as their own lines; already-generated statement snapshots are not rewritten when later reversals post.

Selected no-GL servicing events are statement-visible with `affects_ledger: false`:

- `hold.placed`
- `hold.released`
- `overdraft.nsf_denied`

These rows never change running ledger balance. Non-customer operational rows such as teller drawer variance are excluded unless a future ADR defines a statement-visible rule.

---

## 4. Product configuration

`Products` owns `deposit_product_statement_profiles`, parallel to fee rules and overdraft policies. Statement generation resolves active profiles by product and business date; account behavior must not be inferred from `product_code` alone.

---

## 5. Non-goals

- Teller or customer HTTP routes.
- PDF rendering, document storage, delivery preferences, notices, or notifications.
- Daily balance snapshot tables or reporting extracts.
- Statement fees or statement-copy fees.
- Recomputing prior statement snapshots after late activity.

---

## 6. Worked example

For a monthly statement profile with `cycle_day = 1`, a run on 2026-05-01 can generate the 2026-04-01 through 2026-04-30 statement.

A 100.00 deposit posts a GL 2110 credit and appears as a positive statement line:

```json
{
  "event_type": "deposit.accepted",
  "affects_ledger": true,
  "amount_minor_units": 10000,
  "running_ledger_balance_minor_units": 10000
}
```

A same-period hold appears separately and does not change the running ledger balance:

```json
{
  "event_type": "hold.placed",
  "affects_ledger": false,
  "amount_minor_units": 2500,
  "running_ledger_balance_minor_units": null
}
```
