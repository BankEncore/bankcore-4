# ADR-0008: Money, currency, and rounding policy

**Status:** Accepted  
**Classification:** Core platform (cross-cutting)  
**Aligns with:** [ADR-0002](../adr/0002-operational-event-model.md) (financial fields on operational events), [ADR-0003](../adr/0003-posting-journal-architecture.md) (journal lines), [ADR-0005](../adr/0005-product-configuration-framework.md) (product `currency`)

---

## 1. Purpose

This document defines **authoritative rules** for how BankCORE represents money, identifies currency, and applies rounding so that behavior stays **deterministic, auditable, and safe to evolve** from a single-currency MVP to multi-currency and interest or fee allocation.

Anything that affects **ledger truth, posting batches, or regulatory reporting** MUST follow this policy unless a superseding ADR explicitly documents an exception and its scope.

---

## 2. Definitions

### 2.1 Minor units

**Minor units** are the smallest indivisible accounting unit for a currency as defined by **ISO 4217** (e.g. USD: cents; JPY: whole yen; BHD: fils with three decimal places in major unit terms, expressed as integer minor units).

All persisted **monetary magnitudes** in the financial kernel are stored as **signed or unsigned integers of minor units** (see §5.2), never as floating-point values.

### 2.2 Currency code

**Currency** means an **ISO 4217 alphabetic code** in **uppercase** (e.g. `USD`, `EUR`, `JPY`). Codes MUST be validated against a maintained allowlist (or a generated list from a trusted ISO source) at configuration or input boundaries, not ad hoc strings.

### 2.3 Money tuple

A **money tuple** is the pair **`(amount_minor_units, currency)`**. Either field without the other is incomplete for accounting purposes.

---

## 3. System of record

### 3.1 Authoritative storage

* The **ledger and posting subsystem** (journal entries and lines, posting legs derived for persistence) is the **system of record** for posted monetary amounts.
* **Operational events** carry the business intent amount and currency ([ADR-0002](../adr/0002-operational-event-model.md)); posting MUST NOT silently change currency. Changing magnitude without an explicit rule (fee, FX, rounding policy) is a **defect**.

### 3.2 Single source per aggregate

Each row that stores an amount MUST have a **single** currency column (or inherit currency unambiguously from a parent row, e.g. journal entry → lines). **Do not** store mixed-currency lines on the same journal entry.

---

## 4. Numeric types and Ruby types

### 4.1 Database

* Monetary integer columns MUST use an integer type with sufficient range (**`bigint`** preferred) for worst-case growth and aggregation.
* Use **database constraints** where practical: non-null for posted lines, check constraints for sign rules (see §5), and balancing rules per [ADR-0003](../adr/0003-posting-journal-architecture.md).

### 4.2 Application code (financial paths)

* **`Float` MUST NOT** be used for money amounts in **Core::Ledger**, **Core::Posting**, **Core::OperationalEvents**, or any code path that persists monetary magnitudes.
* **`BigDecimal`** MAY be used **only** in isolated calculation steps that **immediately** round to minor units under an explicit mode (§7) before persistence or before comparison to integers.
* **`Integer`** (minor units) is the default type inside posting and ledger services.

### 4.3 Presentation and APIs

* External APIs MAY expose **decimal strings** (e.g. `"12.34"`) or **structured objects** `{ "amount": "12.34", "currency": "USD" }` for human or integrator convenience.
* Conversion to and from minor units MUST happen at **validated boundaries** using the currency’s **ISO 4217 exponent** (or a vetted internal table that includes exponent and minor-unit digits).

---

## 5. Amounts, signs, and debit or credit

### 5.1 Journal and posting legs

Per [ADR-0003](../adr/0003-posting-journal-architecture.md), each line has a **direction** (debit or credit) and a magnitude. Unless an ADR explicitly defines signed amounts:

* **`amount_minor_units` on journal lines SHOULD be non-negative**, with sign expressed only by **debit or credit** indicator.
* Posting validation (debits equal credits) operates on **magnitudes** in minor units plus direction.

### 5.2 Operational events and user-facing deltas

Event amounts MAY be modeled as **signed minor units** in the event payload if that improves clarity for reversals or direction (e.g. net customer credit). If so, the meaning of the sign MUST be documented per `event_type` and mirrored in posting rules so the **derived journal** still balances.

### 5.3 Zero

Zero amounts are allowed when semantically meaningful (e.g. placeholder legs, waived fees). **Posting batches** MUST still satisfy double-entry equality; “zero-only” batches SHOULD be avoided unless explicitly required for audit narrative.

---

## 6. Naming: `_cents` vs minor units

Existing documentation uses **`amount_cents`** for historical and USD-oriented clarity.

**Semantic rule:** regardless of column name, the integer MUST represent **ISO 4217 minor units** for the row’s currency (for `JPY`, a “cent” field would still hold **whole yen**).

**Naming rule for new schema:**

* **Prefer** `amount_minor_units` (and similar) for new tables or columns to avoid USD-specific misleading names.
* **Allow** `_cents` only where the product is **USD-only** by charter or the team accepts the semantic overload documented above.

---

## 7. Rounding modes

### 7.1 Default rounding mode

Unless a product rule, regulator requirement, or ADR states otherwise, BankCORE uses **half away from zero** at each explicit rounding step when reducing from a higher-precision intermediate to minor units.

**Rationale:** predictable for engineers and auditors; widely implemented in standard libraries. If a domain (e.g. specific interest accrual) requires **banker’s rounding** or **toward zero**, that MUST be named in the product or interest ADR and covered by tests.

### 7.2 When rounding applies

Rounding to minor units MUST occur only at **defined boundaries**, for example:

* converting an external decimal input to minor units;
* completing an interest or fee accrual cycle;
* allocating a total across N legs where division produces a remainder;
* foreign exchange (when introduced): separate FX policy will define **quote precision**, **spread**, and **rounding per leg**.

**Rule:** no implicit rounding inside generic “money math” helpers without a passed-in **RoundingContext** (mode + scale + currency).

---

## 8. Allocation (splitting one total across many legs)

When a total in minor units must be split across **N** lines (fees, tax, multi-GL allocation):

1. Compute **proportional** ideal amounts at a higher precision (e.g. `BigDecimal`) if needed.
2. Floor each line to minor units except one **adjustment** line that receives the **remainder** so the sum **exactly** equals the total.
3. **Determinism:** the algorithm MUST define tie-breaking order (e.g. stable sort by `gl_account_id`, then `line_index`) so the same inputs always yield the same integers.

Document concrete algorithms per use case in the owning domain (e.g. Deposits fee engine) and add regression tests with remainder cases.

---

## 9. Currency compatibility and FX

### 9.1 Single-currency invariant (MVP)

For an institution or environment operating as **single-currency**:

* **Product `currency`**, **account contract currency**, and **event and journal currency** MUST match for any posting path that is in scope.
* Violations MUST fail validation **before** persistence.

### 9.2 Multi-currency (future)

* **No silent conversion.** FX requires explicit rates, timestamps, rate sources, and **separate journal treatment** (gain or loss, separate pairs, or nostro/vostro modeling) under a dedicated ADR.
* **Operational events** that are FX-backed MUST record **both** legs’ currencies and amounts (or references to FX artifacts) as required by that ADR.

### 9.3 Out of scope

Cryptocurrencies, non-ISO instruments, and **non-decimal** custom scrip are out of scope until an ADR defines minor units and validation.

---

## 10. Business date, time zones, and “amount as of”

Monetary amounts on the ledger are **not** time-zone dependent once posted, but **which business date** a post lands on is. See business-date governance in the module catalog and related ADRs: **do not** infer business date from `Time.zone.now` alone without explicit policy.

---

## 11. Third-party libraries (e.g. Money, money-rails)

Use of gems is **optional** and **non-authoritative**:

* Libraries MAY assist with **formatting**, **parsing**, or **boundary DTOs**.
* **Persistence and posting** MUST still use **integer minor units** and this policy’s rounding and allocation rules.
* If a gem’s default rounding differs from §7, **override** or **do not use** that path for kernel calculations.

---

## 12. Testing obligations

Changes that touch money MUST include tests for:

* **conversion** edge cases for the currency’s exponent (e.g. `0.01` USD → `1` minor unit; JPY has no fractional minor unit);
* **balancing** after rounding or allocation (sum of legs equals control total);
* **determinism** (same inputs → same integers);
* **single-currency** mismatch rejection where applicable.

---

## 13. Change control

Amendments to default rounding mode, sign conventions, or storage strategy require:

* an **ADR** or a dated revision of this document with **migration notes** for existing data and code; and
* explicit **data migration** or backfill strategy if historical rows change interpretation.

---

## 14. Summary checklist

| Topic                         | Rule                                                                 |
|------------------------------|----------------------------------------------------------------------|
| Storage                      | Integer **minor units** + ISO **currency** on the aggregate          |
| Floats                       | **Forbidden** in financial kernel paths                              |
| Journal line signs           | Non-negative magnitude + debit or credit unless ADR says otherwise   |
| Rounding default             | **Half away from zero** at explicit boundaries                       |
| Allocation                   | Deterministic remainder placement                                    |
| FX / multi-currency          | **Explicit ADR**; no silent conversion                               |
| Gems                         | Helpers only; integers remain authoritative                          |
