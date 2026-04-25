# ADR-0019: Event catalog metadata and fee operational events (narrow Phase 2)

**Status:** Accepted  
**Date:** 2026-04-26  
**Decision Type:** Operational event vocabulary, read catalog, and posting extension  
**Aligns with:** [ADR-0002](0002-operational-event-model.md) §2.2 (`event_type` registry), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0010](0010-ledger-persistence-and-seeded-coa.md), [ADR-0004](0004-account-balance-model.md) (available balance for fee charge)

---

## 1. Context

`event_type` strings are the persisted registry per ADR-0002. Today, allowlists and posting rules are scattered across [`RecordEvent`, `RecordReversal`, and `PostingRules::Registry` (see repository paths under `app/domains/core/`). Phase 2 roadmap calls for an **event catalog** and the first new financial event pair, **fees**. This ADR locks a **code-first catalog** for discovery and adds the first **fee** pair without a second persistence source of truth for `event_type`. Later accepted narrow slices add interest and NSF/overdraft event types to the same catalog pattern; those later decisions are documented separately.

---

## 2. Decisions

### 2.1 `Core::OperationalEvents::EventCatalog`

- **Purpose:** machine-readable metadata for clients, tests, and drift checks—not a replacement for `operational_events.event_type` strings in the database.
- **Contents:** each known `event_type` exposes at least: **`category`** (`financial` | `servicing` | `operational`), **`posts_to_gl`** (boolean), **`record_command`** (`RecordEvent` | `RecordControlEvent` | `PlaceHold` | `ReleaseHold` | `RecordReversal` | `other`), **`reversible_via_posting_reversal`** (boolean), **`compensating_event_type`** (nullable string; business compensator when not `posting.reversal`).
- **HTTP:** **`GET /teller/event_types`** returns the catalog as JSON (operator auth per [ADR-0015](0015-teller-workspace-authentication.md); no supervisor gate, same posture as other teller reads).

### 2.2 Fee events (`fee.assessed`, `fee.waived`)

- **`fee.assessed`:** Records a **service charge** against an open **demand deposit** (`source_account_id`). **Posting:** Dr **2110** (customer DDA liability, `deposit_account_id` = `source_account_id`) / Cr **4510** Deposit Service Charges (income). **Available balance:** same check as **`withdrawal.posted`** before creating the event (fee reduces spendable balance). **Teller cash session:** **not** required (fees are not teller-cash drawer movements in this slice).
- **`fee.waived`:** Compensates a prior **`fee.assessed`** (MVP: **full** waive of the same `amount_minor_units`). **`reference_id`** (string) **must** equal the **id** of a **posted** **`fee.assessed`** row for the **same** `source_account_id` and **same** amount. **Posting:** Dr **4510** / Cr **2110** with `deposit_account_id` on the Cr leg. **`fee.assessed` is not** reversible via **`posting.reversal`** (`RecordReversal` allowlist unchanged); remediation is **`fee.waived`** only for this MVP.

### 2.3 Drift check

- Automated tests assert every key in **`PostingRules::Registry::HANDLERS`** has a matching **`EventCatalog`** entry with **`posts_to_gl: true`** (and consistent `event_type`), and that the operational-event docs stay aligned with the catalog.

### 2.4 Automated fee assessment (P3-3)

- **P3-3 monthly maintenance engine:** [ADR-0022](0022-monthly-maintenance-fee-engine.md) adds product-owned monthly maintenance fee rules and a system command that creates and posts existing **`fee.assessed`** events.
- No new event type is introduced for routine monthly maintenance fees. Engine-created fees are distinguished by deterministic idempotency keys and **`reference_id`** convention (`monthly_maintenance:<rule_id>:<business_date>`).

---

## 3. Non-goals (this ADR)

- **Interest and NSF / overdraft automation in this ADR.** Later narrow slices add **`interest.accrued`**, **`interest.posted`**, and **`overdraft.nsf_denied`** to the catalog pattern; see [ADR-0021](0021-interest-accrual-and-payout-slice.md) and [ADR-0023](0023-overdraft-nsf-deny-and-fee.md).
- DB-backed catalog tables, admin UI, concept-101 parent/component persistence.

---

## 4. References

- [docs/operational_events/fee-assessed.md](../operational_events/fee-assessed.md), [fee-waived.md](../operational_events/fee-waived.md)
- [ADR-0017 §2.5](0017-deposit-products-fk-narrow-scope.md) observability reads (optional `event_type` filter includes new types)
- [ADR-0021](0021-interest-accrual-and-payout-slice.md) interest accrual and payout event slice
- [ADR-0023](0023-overdraft-nsf-deny-and-fee.md) overdraft NSF denial and fee slice
