# ADR-0011: Accounts deposit MVP addendum (vertical slice 1)

**Status:** Accepted  
**Date:** 2026-04-22  
**Decision Type:** Domain data model and command scope (`Accounts` for first vertical slice)  
**Aligns with:** [ADR-0007](0007-party-account-ownership.md) (participation tables and enums), [ADR-0009](0009-initial-party-persistence-schema.md) (`party_records` FK target), [ADR-0008](0008-money-currency-rounding-policy.md) (single-currency MVP), [docs/architecture/bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md) §6.7, §10

---

## 1. Context

[ADR-0007](0007-party-account-ownership.md) defines **symmetric** participation for **deposit** and **loan** contracts but does not fix **minimal `deposit_accounts` columns**, **product stubbing**, or **which half of the symmetry ships first**. The first vertical slice needs **locked** choices so migrations and `Accounts::Commands::OpenAccount` do not drift.

This ADR is an **addendum**: it narrows implementation for **slice 1** only. It does **not** relax ADR-0007’s participation semantics where those tables exist.

---

## 2. Decision (locked for slice 1)

### 2.1 Loan side (symmetry deferral)

* **Do not** create **`loan_accounts`** or **`loan_account_parties`** migrations until a loan vertical slice is scheduled.
* ADR-0007 remains the **authoritative** shape when loan work starts.

### 2.2 `deposit_accounts` (minimal contract row)

The **Accounts** module owns a new **`deposit_accounts`** table with at least:

| Column            | Type     | Notes |
| ----------------- | -------- | ----- |
| `id`              | bigint   | PK |
| `account_number`  | string   | NOT NULL, **UNIQUE** — institution-unique 12-digit display/reference in the form `1YYMM######C`, where `######` is a global increasing sequence and `C` is a Luhn check digit. |
| `currency`        | string   | NOT NULL, default **`USD`** (ADR-0008 single-currency MVP). |
| `status`          | string   | NOT NULL — application enum for slice 1: **`open`**, **`closed`** (extend only via ADR/catalog when needed). |
| `deposit_product_id` | bigint | NOT NULL, FK → **`deposit_products`** — Phase 2 narrow implementation ([ADR-0017](0017-deposit-products-fk-narrow-scope.md)). |
| `product_code`    | string   | NOT NULL — **denormalized cache** of `deposit_products.product_code` for cheap reads and stable JSON; `OpenAccount` sets it from the resolved product row. **Immutable** `deposit_products.product_code` is policy until a later ADR allows renames. |
| `created_at` / `updated_at` | datetime | |

**Canonical slice-1 product row:** `deposit_products.product_code` **`slice1_demand_deposit`** — seeded in migration / `BankCore::Seeds::DepositProducts`; `OpenAccount` defaults to this product when callers omit `deposit_product_id` / `product_code`.

**Must not** in slice 1: `account_relationships`, restrictions, notes, available balance, holds (see **§4 Non-goals**).

### 2.3 `deposit_account_parties` (first open)

Per [ADR-0007 §2.8](0007-party-account-ownership.md), **`OpenAccount`** always creates a **primary** participation row:

* **`role`:** `owner`
* **`status`:** `active` (do **not** use `pending` for CIP gating in slice 1 unless a later ADR requires it)
* **`effective_on`:** Defaults to **`Core::BusinessDate::Services::CurrentBusinessDate`** (singleton `core_business_date_settings`, migration `20260422130001`; seeds create a row when none exist). **`OpenAccount`** may pass an explicit `effective_on:` for tests or controlled overrides; production paths **must** align with institution bank-date semantics (not silent `Date.current` without review).
* **`ended_on`:** `NULL`

**Two-party joint at open (narrow Phase 2 slice, ADR-0007 vocabulary):** optional **`joint_party_record_id`** creates a **second** row on the same account with **`role: joint_owner`**, **`status: active`**, the **same** **`effective_on`** and **`ended_on: NULL`** as the owner row (no separate override in this slice). **`joint_party_record_id`** MUST reference a distinct existing **`party_records.id`**; if it equals **`party_record_id`**, the command raises **`InvalidJointParty`**; if the joint party is missing, **`JointPartyNotFound`**. **Out of scope:** three or more parties at open, **`authorized_signer` / `beneficiary`** at open, **`pending`** CIP gating for joint, post-open **add/remove joint** (future **`Accounts::Commands::*`**).

### 2.4 `OpenAccount` invariants

* **`party_record_id`** MUST reference an existing **`party_records.id`** (Party domain is system-of-record; Accounts validates via read/query port, not direct mutation of Party tables). Missing primary → **`PartyNotFound`**.
* When **`joint_party_record_id`** is present: second party must exist (**`JointPartyNotFound`** if not); must differ from primary (**`InvalidJointParty`**).
* Enforce ADR-0007 **§2.7** (“at most one open active row per `(deposit_account_id, party_record_id, role)`”) in **application commands** for slice 1.
* **Database:** A **partial unique index** on `deposit_account_parties` (`index_dap_unique_open_active_per_account_party_role`, `WHERE status = 'active' AND ended_on IS NULL`) ships in migration **`20260422130005_create_deposit_account_parties`**, alongside non-unique indexes on `deposit_account_id` and `party_record_id`.

### 2.5 Linking operational events to the deposit account

* **`operational_events.source_account_id`** (nullable bigint, FK → **`deposit_accounts`**) is persisted for slice 1 (migration **`20260422130007_add_source_account_id_to_operational_events`**; column also listed in [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §5). Nullable so non–account-linked event types can exist later.
* **`Core::OperationalEvents::Commands::RecordEvent`** for financial **`deposit.accepted`** **requires** `source_account_id` (open deposit account), idempotency per `(channel, idempotency_key)`, and aligns **`business_date`** with **`CurrentBusinessDate`** unless overridden—see implementation and tests under `app/domains/core/operational_events/` and `test/integration/slice1_vertical_slice_proof_test.rb`.
* **`Core::Posting::Commands::PostEvent`** uses the event row (including amount and `source_account_id` metadata) to post **`deposit.accepted`** to GL **1110** / **2110** per [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §11.

---

## 3. Worked example (slice 1)

**Pre:** `party_records` row `id = 42` exists (from `CreateParty`). Current business date = `2026-04-22`.

**Command:** `Accounts::Commands::OpenAccount` with `party_record_id: 42`, optional **`joint_party_record_id`** (distinct party id) and overrides only as documented (e.g. tests).

**Result:**

1. One **`deposit_accounts`** row: `account_number` unique (for example `126040000013`), `currency: "USD"`, `status: "open"`, **`deposit_product_id`** → seeded **`deposit_products`** row, `product_code: "slice1_demand_deposit"` (cache).
2. One or two **`deposit_account_parties`** rows: primary `party_record_id: 42`, `role: "owner"`, `status: "active"`, `effective_on: 2026-04-22`, `ended_on: NULL`; when joint is supplied, a second row with `role: "joint_owner"` and the same `effective_on` / `ended_on`.

3. **`RecordEvent`** for `deposit.accepted` (with `source_account_id` set to the new **`deposit_accounts.id`**, channel, idempotency key, amount, currency) creates an **`operational_events`** row in **`pending`** status; **`PostEvent`** then moves it to **`posted`** with a balanced journal (1110 / 2110). Posting remains **account-scoped**; it does not branch on joint participation.

---

## 4. Non-goals (slice 1)

* **`loan_accounts` / `loan_account_parties`**
* **`Deposits`** servicing (interest, fees, OD)—catalog §6.8
* **Available balance / holds**—[ADR-0004](0004-account-balance-model.md)
* **Full Products** configuration—ADR-0005; **`product_code`** stub only
* **Post-open joint changes** (`AddPartyToAccount`, remove joint), **`authorized_signer` / `beneficiary`** at open, **3+** parties at open — beyond the narrow two-party **`OpenAccount`** contract in **§2.3**; **`account_relationships`**

---

## 5. Consequences

**Positive:** One clear path for migrations and `OpenAccount`; participation stays ADR-0007–compliant; product and loan complexity deferred without ambiguity.

**Negative:** **`product_code`** is not FK-enforced; typo risk until Products domain exists. **Loan** symmetry is deferred—first loan slice must add tables and revisit tests.

**Neutral:** **`OpenAccount`** / **`RecordEvent`** already depend on **`Core::BusinessDate`**; formal day close and the open-day posting invariant are specified in [ADR-0018](0018-business-date-close-and-posting-invariant.md); further split of “processing date” vs “calendar close” semantics remains a future ADR if needed.

---

## 6. Related ADRs

* [ADR-0007](0007-party-account-ownership.md) — participation model (this ADR implements the **deposit** half first)
* [ADR-0009](0009-initial-party-persistence-schema.md) — `party_records` FK target
* [ADR-0002](0002-operational-event-model.md) — operational events; idempotency and **`source_account_id`** for account-linked financial events
* [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) — ledger tables and **`operational_events`** MVP columns including **`source_account_id`**
* [ADR-0001](0001-modular-monolith-architecture-with-domain-boundaries.md) — `Accounts` vs `Party` vs `Core` boundaries
* [ADR-0018](0018-business-date-close-and-posting-invariant.md) — supervised business date close and posting-day rules

---

## 7. Summary

Vertical slice 1 **ships `deposit_accounts` + `deposit_account_parties`**, with **`OpenAccount`** creating at least one **`owner` / `active`** participation row and optionally a second **`joint_owner` / `active`** row (**§2.3**), **`product_code`** string stub, **`USD`** default currency, ADR-0007 **§2.7** enforced in application commands **and** partial unique index in **`20260422130005`**, **`loan_*`** tables deferred, and **`operational_events.source_account_id`** plus **`RecordEvent`** / **`PostEvent`** / Teller JSON routes for **`deposit.accepted`** (`pending` → `posted`, GL **1110** / **2110**).
