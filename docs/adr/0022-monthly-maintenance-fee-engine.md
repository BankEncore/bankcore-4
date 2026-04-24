# ADR-0022: Monthly maintenance fee engine

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [ADR-0005](0005-product-configuration-framework.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0019](0019-event-catalog-and-fee-events.md)

---

## 1. Context

ADR-0019 added manual `fee.assessed` and `fee.waived` events. Phase 3 needs the first fee engine slice: product configuration should decide when a routine fee is assessed, while posted accounting should continue through the existing `fee.assessed` event and posting rule.

This slice chooses a **monthly maintenance fee** because it is schedule-driven, deterministic, and proves the product-configuration path without transaction-trigger coupling or overdraft policy.

---

## 2. Decision

Add a product-owned `deposit_product_fee_rules` table for minimal fee configuration:

- `deposit_product_id`
- `fee_code` (`monthly_maintenance` in this slice)
- `amount_minor_units`
- `currency`
- `status`
- `effective_on` / `ended_on`
- optional `description`

Add a resolver that returns active fee rules for a product/date, and a system command that:

1. selects open deposit accounts with an active monthly maintenance rule,
2. creates `fee.assessed` using `channel: "system"`,
3. stores engine origin in `reference_id` as `monthly_maintenance:<rule_id>:<business_date>`,
4. uses deterministic idempotency key `monthly-maintenance:<business_date>:<rule_id>:<account_id>`,
5. immediately posts created/replayed pending events with `PostEvent`.

The engine does **not** add a new financial event type. `fee.assessed` remains the durable accounting event.

---

## 3. Outcomes and skips

The command reports per-account outcomes:

- `posted` when a new fee event is created and posted.
- `already_posted` when the deterministic idempotency key has already produced a posted fee.
- `skipped_insufficient_available_balance` when the existing `fee.assessed` available-balance validation rejects the fee.

Other validation errors are treated as unexpected and should fail the run.

---

## 4. Non-goals

- Minimum-balance waivers, relationship waivers, promotional waivers, and complex conditions.
- Transaction-triggered fees and overdraft/NSF fees.
- New fee event types.
- Full ADR-0005 profile/version framework.
- Strong FK from `operational_events` to a fee rule. The engine uses deterministic idempotency plus `reference_id` convention in this slice.

---

## 5. Worked example

Rule:

```json
{
  "deposit_product_id": 1,
  "fee_code": "monthly_maintenance",
  "amount_minor_units": 500,
  "currency": "USD",
  "status": "active",
  "effective_on": "2026-04-01"
}
```

Engine run for account `42` on `2026-04-30` records:

```json
{
  "event_type": "fee.assessed",
  "channel": "system",
  "idempotency_key": "monthly-maintenance:2026-04-30:7:42",
  "amount_minor_units": 500,
  "currency": "USD",
  "source_account_id": 42,
  "reference_id": "monthly_maintenance:7:2026-04-30"
}
```

Posting remains ADR-0019: Dr **2110** / Cr **4510**.
