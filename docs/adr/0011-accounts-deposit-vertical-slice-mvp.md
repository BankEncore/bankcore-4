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
| `account_number`  | string   | NOT NULL, **UNIQUE** — institution-unique display/reference; generation strategy is implementation detail (tests may use random; production may use sequential or another allocator later). |
| `currency`        | string   | NOT NULL, default **`USD`** (ADR-0008 single-currency MVP). |
| `status`          | string   | NOT NULL — application enum for slice 1: **`open`**, **`closed`** (extend only via ADR/catalog when needed). |
| `product_code`    | string   | NOT NULL — **stub** until Products ([ADR-0005](0005-product-configuration-framework.md)); `OpenAccount` sets the **canonical slice-1 literal** below. No `deposit_products` FK in slice 1. |
| `created_at` / `updated_at` | datetime | |

**Canonical `product_code` (slice 1):** the string **`slice1_demand_deposit`** — use in `OpenAccount`, seeds, and slice-1 integration tests so posting and accounts stay aligned until Products replaces it.

**Must not** in slice 1: `account_relationships`, restrictions, notes, available balance, holds (see **§4 Non-goals**).

### 2.3 `deposit_account_parties` (first open)

Per [ADR-0007 §2.8](0007-party-account-ownership.md), **`OpenAccount`** creates **exactly one** participation row for slice 1:

* **`role`:** `owner`
* **`status`:** `active` (do **not** use `pending` for CIP gating in slice 1 unless a later ADR requires it)
* **`effective_on`:** **`Core::BusinessDate`** current processing date when that service exists; until then, the command accepts an explicit `effective_on` **or** uses the same date source agreed for `RecordEvent` (document in command/tests—**must** align with bank-date semantics, not silent `Date.current` in production paths without review)
* **`ended_on`:** `NULL`

**Joint / second party:** out of scope; **`OpenAccount`** accepts a **single** `party_record_id` only.

### 2.4 `OpenAccount` invariants

* **`party_record_id`** MUST reference an existing **`party_records.id`** (Party domain is system-of-record; Accounts validates via read/query port, not direct mutation of Party tables).
* Enforce ADR-0007 **§2.7** (“at most one open active row per `(deposit_account_id, party_record_id, role)`”) in **application commands** for slice 1.
* Add a **partial unique index** matching ADR-0007 §2.7 when status values and migration ordering are stable (same PR or immediate follow-up).

### 2.5 Linking operational events to the deposit account

* **`operational_events`** does not yet carry account FKs in the ledger slice ([ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §5).
* When **`RecordEvent`** / financial **`deposit.accepted`** is implemented, add a migration introducing **`source_account_id`** (nullable bigint, FK → **`deposit_accounts`**, name may be adjusted to match ADR-0002 §8 column roadmap) **in the same work as or immediately before** event payloads that require it—not necessarily bundled with the first **`deposit_accounts`** migration, but **documented** so posting can resolve customer liability from the **account** path.

---

## 3. Worked example (slice 1)

**Pre:** `party_records` row `id = 42` exists (from `CreateParty`). Current business date = `2026-04-22`.

**Command:** `Accounts::Commands::OpenAccount` with `party_record_id: 42`, optional overrides only as documented (e.g. tests).

**Result:**

1. One **`deposit_accounts`** row: `account_number` unique, `currency: "USD"`, `status: "open"`, `product_code: "slice1_demand_deposit"`.
2. One **`deposit_account_parties`** row: `deposit_account_id` → new account, `party_record_id: 42`, `role: "owner"`, `status: "active"`, `effective_on: 2026-04-22`, `ended_on: NULL`.

**Later:** `RecordEvent` for `deposit.accepted` sets `source_account_id` to this `deposit_accounts.id` when that column exists.

---

## 4. Non-goals (slice 1)

* **`loan_accounts` / `loan_account_parties`**
* **`Deposits`** servicing (interest, fees, OD)—catalog §6.8
* **Available balance / holds**—[ADR-0004](0004-account-balance-model.md)
* **Full Products** configuration—ADR-0005; **`product_code`** stub only
* **Joint owners**, **`AddPartyToAccount`**, **`account_relationships`**

---

## 5. Consequences

**Positive:** One clear path for migrations and `OpenAccount`; participation stays ADR-0007–compliant; product and loan complexity deferred without ambiguity.

**Negative:** **`product_code`** is not FK-enforced; typo risk until Products domain exists. **Loan** symmetry is deferred—first loan slice must add tables and revisit tests.

**Neutral:** **`effective_on`** coupling to **`Core::BusinessDate`** may require a small command signature change when BusinessDate lands.

---

## 6. Related ADRs

* [ADR-0007](0007-party-account-ownership.md) — participation model (this ADR implements the **deposit** half first)
* [ADR-0009](0009-initial-party-persistence-schema.md) — `party_records` FK target
* [ADR-0002](0002-operational-event-model.md) — operational events; **`source_account_id`** when events reference accounts
* [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) — current `operational_events` MVP columns; extend per §2.5 above
* [ADR-0001](0001-modular-monolith-architecture-with-domain-boundaries.md) — `Accounts` vs `Party` vs `Core` boundaries

---

## 7. Summary

Vertical slice 1 **ships `deposit_accounts` + `deposit_account_parties` only**, with **`OpenAccount`** creating one **`owner` / `active`** participation row, **`product_code`** string stub, **`USD`** default currency, ADR-0007 **§2.7** enforced in commands first, **`loan_*`** tables deferred, and **`operational_events.source_account_id`** (or equivalent) added when financial events reference an account.
