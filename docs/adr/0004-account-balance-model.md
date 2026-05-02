# ADR-0004: Account & Balance Model

**Status:** Accepted **Date:** 2026-04-19 **Decision Type:** Core Accounting and Funds-Availability Architecture **Classification:** DROP-IN SAFE  
**Addendum:** §13.3 (2026-04-27) — canonical **available** read strategy for Phase 3 prerequisite ([roadmap §12](../roadmap.md)).

---

## 1\. Context

BankCORE requires a clear, regulator-defensible model for account balances and funds availability.

A bank core cannot rely on a single undifferentiated "balance" if it must support:

* holds  
* available-funds checking  
* overdraft and NSF decisions  
* deposit servicing  
* teller controls  
* accurate customer-facing balance presentation  
* operational and audit review

Without an explicit balance model:

* channels may make inconsistent authorization decisions  
* account history may be misleading  
* holds may be applied inconsistently  
* overdraft logic may become fragmented  
* UI, servicing, and accounting layers may each invent their own balance definitions

---

## 2\. Decision

BankCORE will implement a **multi-balance account model** with distinct meanings for ledger, available, and collected/available-for-use concepts, while preserving the journal as the authoritative financial source of truth.

### 2.1 Core principle

Journal-derived ledger balance is the authoritative financial balance, while available funds and other operational balances are derived balances used for authorization, servicing, and customer presentation.

---

## 3\. Balance definitions

### 3.1 Ledger balance

**Definition:** The booked/accounting balance derived from posted journal activity affecting the account.

**Characteristics:**

* authoritative financial balance  
* includes posted debits and credits  
* does not by itself answer whether funds are currently spendable  
* used for accounting truth, statements, and historical reconstruction

### 3.2 Available balance

**Definition:** The amount currently available for withdrawal, transfer, or other authorization-sensitive uses.

**Characteristics:**

* derived from ledger balance  
* reduced by active holds and other applicable constraints  
* may be further adjusted by overdraft eligibility rules or channel-specific authorization rules  
* used for real-time decisioning in teller, API, card, ACH, and similar workflows

### 3.3 Collected balance / collected funds concept

**Definition:** A funds-availability concept representing amounts that are no longer subject to collection delay or uncollected-funds treatment.

**Characteristics:**

* optional in early phases if not fully implemented  
* distinct from ledger balance  
* may affect availability logic depending on product and channel  
* should be modeled explicitly rather than implied if adopted

### 3.4 Memo / pending concepts

**Definition:** Non-posted or provisional effects that may be relevant for operator workflow or preview logic.

**Rule:** Memo or pending values MUST NOT replace journal-backed ledger balance and MUST be clearly distinguished from posted balances.

---

## 4\. Source-of-truth rules

### 4.1 Authoritative financial source

The journal remains the authoritative source of financial truth.

### 4.2 Derived balances

The following may be materialized for performance:

* ledger balance projection  
* available balance projection  
* collected balance projection  
* daily balance snapshots

### 4.3 Projection rule

All projections MUST be:

* derivable from authoritative posted records and applicable hold/funds-availability data  
* rebuildable  
* treated as operational/read-side state, not as primary truth

---

## 5\. Available balance formula

### 5.1 Base rule

At minimum:

`available_balance = ledger_balance - active_holds`

### 5.2 Extensions

Depending on product and policy, available balance may also incorporate:

* uncollected funds restrictions  
* channel-specific authorization holds  
* overdraft limits  
* minimum required reserve logic  
* legal or compliance freezes

### 5.3 Policy rule

Any nontrivial available-balance adjustments MUST be expressed through explicit policy/resolver logic, not scattered ad hoc across controllers or channels.

---

## 6\. Holds model

### 6.1 Purpose

Holds reserve funds or otherwise reduce available balance without changing the posted ledger balance.

### 6.2 Hold characteristics

A hold may include:

* account reference  
* hold amount  
* hold type  
* reason code  
* placed\_at  
* effective\_at  
* expiration\_at  
* released\_at  
* source event or channel reference  
* status

### 6.3 Hold behavior

Holds:

* reduce available balance  
* do not directly alter ledger balance  
* may expire automatically or be released manually  
* must be auditable

### 6.4 Hold lifecycle

Core states should support at least:

* active  
* released  
* expired  
* consumed (if the implementation distinguishes a fulfilled hold from a released hold)

---

## 7\. Overdraft and NSF interaction

### 7.1 Rule

Overdraft and NSF decisions MUST be made against explicit authorization logic, not informal balance checks.

### 7.2 Decision inputs

Authorization logic may consider:

* available balance  
* product overdraft settings  
* account restrictions  
* channel  
* transaction type  
* approval/override status

### 7.3 Outcome

The system should produce a structured decision such as:

* approved within available funds  
* approved via overdraft policy  
* declined for insufficient funds  
* requires override/approval

### 7.4 P3-4 deny + NSF first slice

The first shipped overdraft slice is documented in [ADR-0023](0023-overdraft-nsf-deny-and-fee.md):

* `withdrawal.posted` and `transfer.completed` attempts that exceed available balance are denied, not posted;
* denial is audited with posted no-GL `overdraft.nsf_denied`;
* a product-configured NSF fee may be force-posted as `fee.assessed`, linked to the denial by `reference_id`;
* allowing overdrafts into a limit remains a future slice.

---

## 8\. Posting interaction

### 8.1 Ledger effect

Posted financial transactions change ledger balance through the posting and journal pipeline defined in ADR-0003.

### 8.2 Hold effect

Holds affect available balance independently of journal-posted financial balance.

### 8.3 Rule

No hold, authorization check, or UI action may silently mutate ledger balance outside the posting pipeline.

---

## 9\. Account history and presentation

### 9.1 Customer and operator presentation

The system SHOULD present balances with clear labeling, including where relevant:

* ledger balance  
* available balance  
* hold total  
* collected balance (if implemented)

### 9.2 History rule

Transaction history should distinguish between:

* posted financial activity  
* holds and releases  
* pending/memo items

The UI MUST avoid presenting derived or provisional balances as though they were booked ledger truth.

### 9.3 P3-5 generated statements

Generated deposit statements are immutable snapshots owned by the `Deposits` domain and configured by product-owned statement profiles. Statement ledger lines are derived from posted GL **2110** `journal_lines` for the account subledger; selected no-GL servicing events such as holds and NSF denials may appear as non-ledger activity. See [ADR-0024](0024-customer-visible-history-and-statements.md).

---

## 10\. Daily snapshots and reporting

### 10.1 Snapshot support

BankCORE MAY maintain daily balance snapshots for:

* ledger balance  
* available balance  
* collected balance (if implemented)

### 10.2 Reporting rule

Historical reporting SHOULD rely on explicit snapshot/projection logic rather than attempting to infer all prior availability states from current balances alone.

---

## 11\. Constraints

### 11.1 Required rules

* ledger balance must come from posted financial activity  
* available balance must be explicitly derived  
* holds must be separate records with lifecycle state  
* overdraft/NSF decisions must use formal authorization logic  
* projections must be rebuildable

### 11.2 Prohibited patterns

* storing one ambiguous `balance` and using it for every purpose  
* reducing ledger balance to reflect a hold  
* channel-specific balance formulas embedded directly in controllers  
* treating available balance projection as authoritative accounting truth

---

## 12\. Consequences

### Positive

* clear financial vs operational balance semantics  
* cleaner authorization and overdraft logic  
* better auditability of funds availability decisions  
* clearer UI and reporting semantics  
* stronger foundation for deposit servicing and card/ACH/channel expansion

### Negative

* additional modeling complexity  
* more projections and reconciliation checks to maintain  
* requires disciplined terminology across product, UI, and services

---

## 13\. Implementation guidance

### 13.1 Minimum implementation

At minimum, BankCORE should support:

* journal-derived ledger balance  
* active hold tracking  
* derived available balance  
* formal authorization decision service

### 13.2 Expansion path

Later phases may add:

* collected funds modeling  
* channel-specific authorization hold types  
* Reg CC-style availability controls  
* richer pending/memo transaction support  
* balance-basis policies per product behavior

### 13.3 Canonical available balance read strategy (addendum, 2026-04-27)

This addendum closes [roadmap §12 “Available balance”](../roadmap.md): **compute-on-read vs materialized projection**.

1. **Default (canonical for authorization and servicing in this repo)** — **Compute-on-read:** `Accounts::Services::AvailableBalanceMinorUnits` (or a successor service under **`Accounts`**) implements available balance as **ledger(2110 subledger for `deposit_account_id`) minus active holds**, per §5.1 and [ADR-0013](0013-holds-available-and-servicing-events.md). No separate **materialized available** table or column is required for correctness.

2. **Materialized projection (allowed, not default)** — §4.2–4.3 still apply: a stored **available** (or ledger) projection **may** be introduced for performance if it remains **derivable from posted journals + holds**, **rebuildable**, and **read-side only**—never authoritative for GL truth.

3. **When to introduce projection** — Require a **dedicated ADR** (or major addendum) that specifies storage, **every invalidation path** (e.g. `PostEvent`, hold place/release, and any command that changes effective holds or policy), reconciliation/rebuild jobs, and **explicit product triggers** (e.g. p95/p99 authorization latency SLOs breached, or hot-account / high-QPS channel requirements). Do not add projection speculatively before metrics justify it. The proposed implementation contract is [ADR-0038](0038-account-balance-projections-and-daily-snapshots.md).

4. **Performance before projection** — Prefer query and index tuning (e.g. composite index on `journal_lines` matching the ledger filter for **2110** + `deposit_account_id`) and bounded read patterns; treat snapshot / running-balance patterns as **separate** ADRs when compute-on-read is no longer sufficient.

---

## 14\. Related ADRs

* ADR-0001: Modular Monolith Architecture with Domain Boundaries  
* ADR-0002: Operational Event Model  
* ADR-0003: Posting & Journal Architecture  
* ADR-0013: Holds, available balance, and servicing operational events
* ADR-0038: Account balance projections and daily snapshots

---

## 15\. Summary

BankCORE adopts a **multi-balance account model** in which:

* **ledger balance** is the authoritative booked financial balance  
* **available balance** is a derived funds-availability balance  
* **holds** are separate, auditable constraints on available funds  
* **overdraft and NSF behavior** is governed by explicit authorization logic  
* **available balance for authorization** defaults to **compute-on-read** from journals and holds (§13.3); materialized projections are optional optimizations, gated by ADR and product SLOs

This decision prevents ambiguity between accounting truth and operational availability, and provides the foundation required for reliable teller operations, deposit servicing, and future channel expansion.