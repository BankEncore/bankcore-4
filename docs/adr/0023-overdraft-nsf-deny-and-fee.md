# ADR-0023: Overdraft NSF deny and fee

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [ADR-0004](0004-account-balance-model.md), [ADR-0005](0005-product-configuration-framework.md), [ADR-0019](0019-event-catalog-and-fee-events.md)

---

## 1. Context

Today `withdrawal.posted`, `transfer.completed`, and `fee.assessed` reject when available balance is insufficient. ADR-0004 requires overdraft and NSF behavior to be explicit authorization logic, not ad hoc balance checks.

The first overdraft slice chooses the safest branch behavior: deny attempted debits that exceed available balance, audit the denial, and assess a product-configured NSF fee.

---

## 2. Decision

Add a product-owned `deposit_product_overdraft_policies` table. The first supported mode is **`deny_nsf`** with a configured **`nsf_fee_minor_units`**.

When a `withdrawal.posted` or `transfer.completed` attempt exceeds available balance:

1. Do **not** create or post the attempted withdrawal/transfer.
2. Record a posted no-GL operational event **`overdraft.nsf_denied`**.
3. Force-create and post a system-channel **`fee.assessed`** NSF fee, linked to the denial by `reference_id = "nsf_denial:<denial_event_id>"`.

The forced NSF fee is an explicit product-policy exception to the normal `fee.assessed` available-balance guard. It is only allowed when linked to a posted `overdraft.nsf_denied` event for the same account.

---

## 3. Event and posting semantics

### `overdraft.nsf_denied`

- Category: operational.
- Posting: none.
- Status: posted at creation.
- Carries attempted amount/currency, `source_account_id`, optional `destination_account_id`, actor, channel, and `reference_id` describing attempted type (`attempt:withdrawal.posted` or `attempt:transfer.completed`).

### NSF fee

- Event type: existing `fee.assessed`.
- Channel: `system`.
- Idempotency key: `nsf-fee:<denial_event_id>`.
- Reference: `nsf_denial:<denial_event_id>`.
- Posting: existing ADR-0019 Dr **2110** / Cr **4510**.

---

## 4. Non-goals

- Allowing overdraft transactions to post into a configured limit.
- NSF/OD fee waivers beyond existing `fee.waived`.
- Reg E opt-in, real-time channel limits, retry representment, or returned-item lifecycle.
- Separate NSF fee GL mapping.
- Materialized available-balance projection.

---

## 5. Worked example

A customer with 100 available attempts a 500 withdrawal under a product policy with a 35.00 NSF fee.

Denied audit:

```json
{
  "event_type": "overdraft.nsf_denied",
  "status": "posted",
  "channel": "teller",
  "idempotency_key": "withdrawal-attempt-1:nsf-denied",
  "amount_minor_units": 500,
  "currency": "USD",
  "source_account_id": 42,
  "reference_id": "attempt:withdrawal.posted"
}
```

Forced NSF fee:

```json
{
  "event_type": "fee.assessed",
  "channel": "system",
  "idempotency_key": "nsf-fee:1001",
  "amount_minor_units": 3500,
  "currency": "USD",
  "source_account_id": 42,
  "reference_id": "nsf_denial:1001"
}
```

The attempted withdrawal is not recorded as `withdrawal.posted`.
