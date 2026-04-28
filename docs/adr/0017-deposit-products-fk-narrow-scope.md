# ADR-0017: Deposit products table + FK (Phase 2 narrow scope)

**Status:** Accepted  
**Date:** 2026-04-26  
**Decision Type:** Products / Accounts persistence  
**Aligns with:** [ADR-0005](0005-product-configuration-framework.md) (framework vision; this ADR is an **intentionally narrow** slice), [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) (deposit account shape), [ADR-0016](0016-trial-balance-and-eod-readiness.md) / [ADR-0018](0018-business-date-close-and-posting-invariant.md) (read date bounds and envelope semantics for observability), [module catalog](../architecture/bankcore-module-catalog.md) §6.x `Products` ownership

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

### 2.5 Observability reads (Phase 2 narrow slice)

Read APIs that list **`operational_events`** across **closed and open** business days (relative to singleton **`current_business_on`**) **must**:

- **Bound dates** like ADR-0016 reporting: no **`business_date`** (or range end) **strictly after** `Core::BusinessDate::Services::CurrentBusinessDate`; malformed ISO dates → **422** `invalid_request`.
- **Expose envelope context** like ADR-0018 EOD reads: response includes **`current_business_on`** and **`posting_day_closed`**, where **`posting_day_closed`** is **true** when the requested window’s end date is **strictly before** `current_business_on` (historical window); **false** when the window includes the open day (end date equals `current_business_on`).
- **Cap range width** (implementation: max **31** consecutive `business_date` values per request) and paginate (keyset `after_id` + `limit`) to avoid unbounded scans.
- **Product identity on account-linked rows:** when an event references **`source_account_id`** and/or **`destination_account_id`**, list responses include a nested **`source_account`** / **`destination_account`** object (when present) with **`id`**, **`account_number`**, **`deposit_product_id`**, **`product_code`**, and **`product_name`** (from the linked **`deposit_products`** row)—stable identifiers per §2.1–2.2.
- **Operating-unit attribution:** after ADR-0032, staff-originated internal events on `teller` and `branch` channels carry **`operating_unit_id`** where scope can be resolved. List responses include this id for branch/support evidence, but it remains operational scope only; it does not imply branch-level ledger, branch business date, or account ownership.
- **Optional filters:** **`deposit_product_id`** and/or **`product_code`** restrict to events whose **source or destination** account matches the filtered product(s) (conjunction on account attributes when both are supplied).
- **Traceability (read-only):** each event row may include **`posting_batch_ids`** and **`journal_entry_ids`** (no embedded GL lines; trial balance remains the GL aggregate read path per ADR-0016).

**HTTP:** **`GET /teller/operational_events`** — same operator header posture as other teller reads ([ADR-0015](0015-teller-workspace-authentication.md)); **no supervisor-only gate** in this slice (matches ADR-0016 trial balance / EOD GETs).

---

## 3. Consequences

- Seeds and migrations must ensure at least one **`deposit_products`** row exists before **`deposit_accounts`** require `deposit_product_id` (migration backfills existing accounts).
- Full ADR-0005 “behavior from configuration only” remains a **north star**; this ADR does not claim compliance with §5.2 resolvers yet.

---

## 4. References

- Implementation: `Products::Models::DepositProduct`, `Products::Queries::FindDepositProduct`, `Accounts::Commands::OpenAccount`, `BankCore::Seeds::DepositProducts`, migrations `20260424120003` / `20260424120004`.
- Observability listing: `Core::OperationalEvents::Queries::ListOperationalEvents`, `Teller::OperationalEventsController#index`.
