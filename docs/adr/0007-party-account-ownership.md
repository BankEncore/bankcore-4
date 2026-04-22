# ADR-0007: Party–account participation

**Status:** Proposed  
**Date:** 2026-04-21  
**Decision Type:** Domain data model (Accounts ↔ Party linkage)  
**Aligns with:** [ADR-0006](0006-canonical-party-cif-model.md) §8 (party-to-account relationships), [ADR-0009](0009-initial-party-persistence-schema.md) (`party_records` as FK target), [docs/architecture/bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md) §10 (single-owner tables)

---

## 1. Context

[ADR-0006](0006-canonical-party-cif-model.md) requires that **party identity** and **party-to-account roles** stay separate concerns: who someone is must not be collapsed into “rows on an account.” [ADR-0009](0009-initial-party-persistence-schema.md) defines the first relational shape for **identity** (`party_records` and subtype profiles) and explicitly **excludes** participation on accounts.

We still need a durable, auditable way to record **which parties participate on which account contracts**, with what **role**, over what **time range**, and with what **servicing status**—without overloading Party tables or inferring relationships from balances or journals.

---

## 2. Decision

### 2.1 Owning module and physical shape

The **Accounts** module owns first-cut persistence for party participation on **deposit** and **loan** account contracts, as **two symmetric tables** (no polymorphic “account” FK in MVP):

* `deposit_account_parties` — links `party_records` to `deposit_accounts`
* `loan_account_parties` — links `party_records` to `loan_accounts`

**Rationale:** The account contract (deposit or loan) is the natural aggregate boundary for “who is on this account” for servicing and invariants; Party remains the system-of-record for **identity** only. Two tables mirror the existing catalog split between `deposit_accounts` and `loan_accounts` and keep foreign keys simple and enforceable.

### 2.2 Scope

**In scope**

* Participation rows: FK to the appropriate account table, FK to `party_records` ([ADR-0009](0009-initial-party-persistence-schema.md))
* `role` (string; closed set documented below; application-enforced for MVP)
* Business-date-oriented validity: `effective_on`, `ended_on` (dates; nullable `ended_on` means “still open”)
* `status` for servicing workflow (string; closed set documented below)
* Timestamps for row audit (`created_at`, `updated_at`)

**Out of scope**

* Party profile / subtype columns ([ADR-0009](0009-initial-party-persistence-schema.md))
* Party↔party relationships ([ADR-0006](0006-canonical-party-cif-model.md) §7)
* Product configuration matrices ([ADR-0005](0005-product-configuration-framework.md))
* Posting, journals, GL, or operational-event payloads ([ADR-0003](0003-posting-journal-architecture.md), [ADR-0010](0010-ledger-persistence-and-seeded-coa.md)) — **ledger truth must not imply or replace participation rows**

### 2.3 Enumerations (documentation only)

As with [ADR-0009](0009-initial-party-persistence-schema.md) §2.2, treat the closed sets below as **canonical application enums**. **Initial migrations do not add** PostgreSQL enum types or `CHECK` constraints for `role` or `status`; validation and transitions live in the Accounts domain until we deliberately add database-level constraints.

### 2.4 Role values (`role` column)

Aligned with [ADR-0006](0006-canonical-party-cif-model.md) §8.2 examples (wording normalized for storage):

| Value               | Meaning (summary) |
| ------------------- | ----------------- |
| `owner`             | Primary owner / sole owner context as applicable |
| `joint_owner`       | Joint owner on the contract |
| `authorized_signer` | Signatory authority without implying sole ownership |
| `beneficiary`       | Beneficiary capacity on the account relationship |
| `trustee`           | Trustee capacity |
| `custodian`         | Custodian capacity |
| `other`             | Reserved for institution-defined roles until a later ADR splits them |

Extensions beyond this set require an ADR or catalog update so role vocabulary stays coherent across channels.

### 2.5 Status values (`status` column)

Minimal MVP set:

| Value      | Meaning (summary) |
| ---------- | ------------------- |
| `pending`  | Participation proposed or awaiting completion of prerequisites (e.g. CIP) |
| `active`   | Participation in force for servicing within the effective window |
| `inactive` | Participation ended or superseded; row retained for history |

### 2.6 Time semantics

* **`effective_on`** — first calendar date on which this participation row is intended to count for servicing and reporting (required).
* **`ended_on`** — last calendar date of effect, inclusive; **`NULL` means open-ended** (still effective after `effective_on`, subject to `status`).
* **Rationale for dates (not timestamps):** aligns with business-date and servicing language in core banking; precise time-of-day can be added later if a product line requires it.

### 2.7 Uniqueness and history

**Rule:** At most **one “open” participation** per `(account_id, party_record_id, role)` at a time, where **open** means: `status = active` **and** `ended_on IS NULL`.

* **History:** Closing a participation sets `ended_on` (and typically `status` to `inactive`). **Adding** a new period for the same triple uses a **new row** with a new `effective_on` (and new `id`). Do not reuse the same row to span disjoint periods.
* **Enforcement:** express as a **partial unique index** in a future migration (example condition: `status = 'active' AND ended_on IS NULL`). Until that migration ships, enforce in application commands.

`pending` rows may temporarily overlap by product policy; if overlap becomes disallowed, state the rule in Accounts commands and optionally tighten the index.

### 2.8 Table sketches (symmetric)

Column lists are **logical**; physical names and nullability follow Rails conventions when implemented.

#### `deposit_account_parties`

| Column               | Type     | Constraints / notes |
| -------------------- | -------- | -------------------- |
| `id`                 | bigint   | PK |
| `deposit_account_id` | bigint   | FK → `deposit_accounts`, not null |
| `party_record_id`    | bigint   | FK → `party_records`, not null |
| `role`               | string   | not null; see §2.4 |
| `status`             | string   | not null; see §2.5 |
| `effective_on`       | date     | not null |
| `ended_on`           | date     | nullable |
| `created_at`         | datetime | |
| `updated_at`         | datetime | |

#### `loan_account_parties`

Same columns, with `loan_account_id` (FK → `loan_accounts`) replacing `deposit_account_id`.

### 2.9 Domain boundaries

* **Accounts** owns migrations, models, and **commands** that insert, update, or end participation rows on `deposit_account_parties` and `loan_account_parties`.
* **Party** may **read** participation through queries or explicit application APIs exposed for CIF screens, but **must not** mutate these tables directly (no writes from `Party::*` commands into Accounts-owned tables). Cross-domain workflows orchestrate via public contracts or application services, consistent with [bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md) §9 dependency rules.

---

## 3. Consequences

**Positive**

* Clear **single owner** for account-party persistence (Accounts), matching modular monolith rules.
* Simple FKs to `deposit_accounts` / `loan_accounts` without polymorphism in MVP.
* Explicit history via `effective_on` / `ended_on` and row replacement supports audit and servicing.

**Negative**

* **Two tables** duplicate column and role semantics; product-specific divergence must be watched.
* Partial unique indexes and “open row” rules require discipline in tests and commands.

**Neutral**

* A future ADR may introduce a unified abstraction or additional account product lines; this ADR should be **superseded explicitly** rather than silently diverging.

---

## 4. Related ADRs

* [ADR-0003](0003-posting-journal-architecture.md) — posting does not define party roles  
* [ADR-0004](0004-account-balance-model.md) — balances and account state (orthogonal to participation layout)  
* [ADR-0005](0005-product-configuration-framework.md) — product behavior vs party-on-account contract  
* [ADR-0006](0006-canonical-party-cif-model.md) — conceptual party-to-account separation  
* [ADR-0009](0009-initial-party-persistence-schema.md) — `party_records` / profiles (FK target for `party_record_id`)  
* [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) — ledger tables do not encode CIF participation  
* [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) — **deposit-only** slice 1 addendum (`deposit_accounts`, first `OpenAccount`, defer `loan_*`)

---

## 5. Summary

BankCORE records party participation on deposit and loan accounts in **`deposit_account_parties`** and **`loan_account_parties`**, owned by **Accounts**, with documented role/status strings, business-date validity, and a single open active row per `(account, party, role)` enforced in domain and eventually by partial unique index. Party identity tables remain under **Party** per ADR-0009; posting and GL remain orthogonal per ADR-0003 / ADR-0010.
