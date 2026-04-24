# ADR-0017: Deposit products table + FK (Phase 2 narrow scope)

**Status:** Accepted  
**Date:** 2026-04-26  
**Decision Type:** Products / Accounts persistence  
**Aligns with:** [ADR-0005](0005-product-configuration-framework.md) (framework vision; this ADR is an **intentionally narrow** slice), [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) (deposit account shape), [module catalog](../architecture/bankcore-module-catalog.md) §6.x `Products` ownership

---

## 1. Context

Slice 1 stored **`product_code`** as a string on **`deposit_accounts`** without a product row. Phase 2 needs a **durable product identity** for upcoming work (joint accounts, richer servicing) without implementing the full **resolver / profile** stack from ADR-0005 in one change set.

---

## 2. Decision

### 2.1 Table ownership

- **`deposit_products`** is owned by the **`Products`** module (`Products::Models::DepositProduct`).
- **`deposit_accounts.deposit_product_id`** is a **required** FK to **`deposit_products`**.
- **`deposit_accounts.product_code`** remains a **denormalized write-through cache** copied from the linked product’s `product_code` at `OpenAccount` time. **Policy:** `deposit_products.product_code` is **immutable** in MVP (no in-place renames); new codes add new rows or follow a future ADR.

### 2.2 Minimal product columns (this slice)

| Column         | Notes |
| -------------- | ----- |
| `product_code` | Unique, stable string |
| `name`         | Display / ops label |
| `status`       | `active` / `inactive` (application enum) |
| `currency`     | Aligns with ADR-0008 single-currency MVP default **USD** |

**Out of scope here:** `gl_mapping_profile_id`, interest/fee/limit profiles, `ProductResolver` / `GlMappingResolver`, per-product posting legs — **posting remains** on the existing posting rule registry until a dedicated posting ADR extends behavior.

### 2.3 `OpenAccount`

- Resolves product by optional **`deposit_product_id`** or **`product_code`**, or defaults to the seeded **`slice1_demand_deposit`** row.
- If **both** `deposit_product_id` and `product_code` are supplied, they must refer to the **same** product or **`OpenAccount`** raises **`ProductConflict`**.

### 2.4 HTTP

- **`POST /teller/deposit_accounts`** accepts optional `deposit_product_id` / `product_code` in the `deposit_account` object; response includes **`deposit_product_id`**, **`product_code`**, and **`product_name`**.

---

## 3. Consequences

- Seeds and migrations must ensure at least one **`deposit_products`** row exists before **`deposit_accounts`** require `deposit_product_id` (migration backfills existing accounts).
- Full ADR-0005 “behavior from configuration only” remains a **north star**; this ADR does not claim compliance with §5.2 resolvers yet.

---

## 4. References

- Implementation: `Products::Models::DepositProduct`, `Products::Queries::FindDepositProduct`, `Accounts::Commands::OpenAccount`, `BankCore::Seeds::DepositProducts`, migrations `20260424120003` / `20260424120004`.
