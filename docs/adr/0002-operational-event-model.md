# ADR-0002: Operational Event Model

**Status:** Accepted 
**Date:** 2026-04-19 
**Decision Type:** Core Domain Architecture
**Supersedes:** none
**Superseded By:** none

---

## 1\. Context

BankCORE requires a consistent, auditable, and extensible way to represent all business actions that have financial or operational impact.

Without a standardized event model:

* transaction logic becomes fragmented across modules  
* auditability is weakened  
* reversal behavior becomes inconsistent  
* integration points become unclear

Modern core banking systems increasingly use **event-based models** to normalize activity before applying accounting and downstream processing.

---

## 2\. Decision

BankCORE will implement a **canonical Operational Event Model** as the authoritative representation of all business actions.

### 2.1 Core principle

Every material business action MUST be represented as an Operational Event.

This includes:

* financial transactions  
* servicing actions (fees, interest, holds)  
* operational actions (session open/close, overrides)

### 2.2 Event `event_type` registry (MVP)

Canonical **`event_type`** strings (dotted codes such as `deposit.accepted` in §5) are the **application registry** for MVP. [docs/concepts/101-operational_event_enums_concept.md](../concepts/101-operational_event_enums_concept.md) supplies **parent/component vocabulary** for product and analytics; mapping from persisted `event_type` to concept-101 families is **documentation or a future mapping ADR**, not a second source of truth in the row. New `event_type` values require catalog or ADR review so posting and reporting stay aligned.

---

## 3\. Event lifecycle

### 3.1 Standard flow

1. Event is **created** (Operational Event recorded)  
2. Event is **validated/classified**  
3. Event is **posted** (via Posting Engine)  
4. Event produces **journal entries**  
5. Event becomes part of **immutable history**

### 3.2 Persisted status across layers (MVP)

Three different tables each persist a `status` string. The values **look similar** but mean **different things**; code and reviews must not reuse one enum across layers.

| Layer | Table | MVP `status` values (application enum) | Meaning |
| ----- | ----- | ---------------------------------------- | ------- |
| Business event | `operational_events` | `pending`, `posted` | **Intent / business lifecycle** of the operational event: accepted and not yet completed (`pending`); business outcome recorded and posting has completed successfully (`posted`). |
| Posting pipeline | `posting_batches` | `pending`, `posted`, `failed` | **Technical outcome** of applying the event through the posting engine for this batch (see [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §6). |
| Ledger | `journal_entries` | `posted` (only in MVP) | **Ledger row state**; MVP creates only committed rows (see [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §7). |

**Naming rule:** `failed` is for **`posting_batches`** only in MVP. Do not overload `operational_events.status` with posting-engine failures unless a future ADR introduces a distinct business state (e.g. `rejected` / `cancelled`) and documents transitions.

#### Transitions (MVP)

**`posting_batches`**

* `pending` → `posted` when journal entry (and lines) for this batch commit successfully.  
* `pending` → `failed` when posting aborts without a balanced committed journal for this batch (exact rules live in posting domain code and tests).

**`operational_events`**

* `pending` → `posted` when the event’s posting is considered **successful for the business** (typically: associated `posting_batches` reach `posted` and required journal exists). If posting never succeeds, the event remains `pending` or moves only to a **separately named** business state if you add one later—not to `failed` (reserve `failed` for batches).

**`journal_entries`**

* Rows are created already `posted` in MVP; no `pending` journal workflow yet.

#### Reversals vs `status`

Per §6, a reversal is a **new** operational event that produces compensating journal entries. Under strict §6.1 immutability, the **original** operational event row remains **`posted`**; do not represent “undone” by updating the original row to a different `status`. “Was reversed” is derived from reversal linkage (`reversal_of_event_id` / `reversed_by_event_id` when those columns exist) and/or the existence of the compensating event—not from flipping the original’s `status`.

#### Authoritative slice detail

Column-level notes for the ledger slice tables remain in [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §5–7; this subsection is the **cross-layer** vocabulary and transition contract so ADR-0002 and ADR-0010 stay aligned.

### 3.3 Event composition (single-level default)

**Default:** Persist **one `operational_events` row** per customer/business action (single-level header). Idempotency and lifecycle anchor on that header.

**Avoid:** System-wide **`operational_event_lines` (or equivalent) for every `event_type`**, which raises baseline complexity (invariants, partial failure, duplication vs journal) for naturally single-leg flows.

**Structured breakdown only where complexity earns it:**

| Pattern | Rationale | Mechanisms (document per flow) |
| -------- | ---------- | ------------------------------ |
| **Mixed deposits** (cash + multiple checks + on-us official checks, etc.) | Holds and clearance attach to **individual instruments**, not a single rolled-up amount | First-class **child rows** (instrument / line table) or a **typed JSON payload** with explicit per-instrument fields—document which and when lines are mandatory. |
| **Loan payments** (principal + interest + fees) | Stable **economic buckets** under one customer action | Often **header + fixed columns or small typed payload**; add **lines** only if variable leg counts, multi-loan splits, or instrument-level concerns appear. |

**Rule of thumb:** Require an explicit per-line or typed-child breakdown when the action contains **more than one independent hold/clearance subject** (or equivalent) and cannot be serviced safely from one aggregate amount alone. Physical shape (payload vs lines) is **per event family**, not global.

---

## 4\. Event structure

Each operational event MUST include:

### 4.1 Core fields

* `event_type` (enum, canonical registry; see §2.2)  
* `status` — persisted values for MVP: `pending`, `posted` (semantics and cross-table `status` vocabulary: **§3.2**; not `reversed` on the same row under §6.1)  
* `business_date`  
* `effective_at`  
* `actor_id`  
* `channel` (teller, api, batch, etc.)  
* `reference_id` (external or correlation)  
* `idempotency_key`

### 4.2 Financial context

* `amount_cents` (if applicable)  
* `currency`  
* `source_account_id`  
* `destination_account_id`

### 4.3 Metadata

* structured JSON payload for domain-specific attributes  
* linkage to related records (teller session, document, etc.)

### 4.4 Reversal linkage

* `reversal_of_event_id`  
* `reversed_by_event_id`

---

## 5\. Event categories

Events SHOULD be grouped into categories:

### 5.1 Financial events

* deposit.accepted  
* withdrawal.posted  
* transfer.completed  
* fee.assessed  
* interest.accrued  
* interest.posted

### 5.2 Servicing events

* hold.placed  
* hold.released  
* overdraft.triggered  
* maturity.processed

### 5.3 Operational events

* teller\_session.opened  
* teller\_session.closed  
* override.requested  
* override.approved

---

## 6\. Reversals

### 6.1 Rule

Events MUST NOT be mutated after posting.

Corrections MUST be handled via **reversal events**.

### 6.2 Requirements

* reversal creates a new event  
* reversal links to original event  
* reversal generates compensating journal entries  
* audit trail remains intact

---

## 7\. Idempotency

All externally triggered events MUST support idempotency.

### 7.1 Policy

Duplicate submissions MUST NOT create duplicate financial impact. Persistence rules for keys, channels, and replay behavior are **§7.3**.

### 7.2 Outcome

* Successful idempotent retries return the **same** operational event identity and do not double-post.  
* Semantically different requests that reuse the same idempotency scope MUST be rejected (see §7.3).

### 7.3 Persistence (MVP)

**Uniqueness:** At most one `operational_events` row per **`(channel, idempotency_key)`**. The pair is the idempotency scope for external retries.

**`channel`:** Required string identifying the submission path (canonical values documented as application enums for MVP, e.g. `teller`, `api`, `batch`, `system`). Values are not interchangeable across channels for the same opaque `idempotency_key`.

**`idempotency_key`:** Opaque string chosen by the **client** for external channels. Stored **exactly** as received (no normalization unless a future ADR specifies it).

**Create replay:** If an event already exists for the same `(channel, idempotency_key)`, the application **returns the existing row** (same primary key and stable API representation) and **does not** insert a duplicate. This applies while the event is `pending` (e.g. posting not yet successful) and after `posted` (read-only replay).

**Semantic mismatch:** If a request reuses `(channel, idempotency_key)` but differs in **material fields** from the stored event, respond with **409 Conflict** and a stable error code—do **not** return the existing event as if the new request succeeded. **Slice 1 `deposit.accepted`:** the application hashes a stable payload including **`event_type`**, **`channel`**, **`idempotency_key`**, **`amount_minor_units`**, **`currency`**, and **`source_account_id`** for mismatch detection (see **`Core::OperationalEvents::Commands::RecordEvent`**). Extend the fingerprint explicitly when new persisted columns participate in idempotency for other `event_type` values.

**Strict posting alignment:** Replays against a `posted` event must not update the row; they only surface persisted state.

**Migration from global uniqueness:** Databases created under an earlier slice may have a **unique index on `idempotency_key` alone**. Migrate by: (1) add `channel` with a temporary default such as `legacy` for existing rows; (2) backfill `channel` where origin is known; (3) add **`UNIQUE (channel, idempotency_key)`**; (4) **drop** the old unique index on `idempotency_key` only after verifying no violations under the new scope. Document integrator impact: keys are now unique **per channel**, not globally.

---

## 8\. `operational_events` column roadmap and audit

Authoritative **MVP column list** for the ledger slice is tabulated in [ADR-0010](0010-ledger-persistence-and-seeded-coa.md) §5; this section is the **conceptual gap** vs §4 and the **near-term slice** plan.

### 8.1 Gap (concept §4 vs MVP persistence)

| Conceptual field (§4) | MVP table today | Note |
| --------------------- | ----------------- | ---- |
| `effective_at` | not persisted | **Slice A:** add when integrations require server timestamp of intent. |
| `actor_id` | not persisted | **Slice B:** workspace / operator identity. |
| `channel` | persisted (idempotency §7.3) | Required for scoped idempotency; aligns with §4.1. |
| `reference_id` / correlation | not persisted | **Slice A:** external trace (wire ref, file id, etc.). |
| Reversal FKs | not persisted | **Slice A** when reversal commands ship. |
| JSON metadata | not persisted | **Slice C:** versioned payload per `event_type` when needed. |
| `amount_cents` (§4 wording) | `amount_minor_units` (ADR-0008) | Naming: use minor units in schema (ADR-0010). |
| `source_account_id` (§4.2) | persisted — nullable FK → **`deposit_accounts`** | **Slice 1:** required for **`deposit.accepted`** financial path; idempotency mismatch logic includes it alongside type/amount/currency ([ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) §2.5). |
| `destination_account_id` (§4.2) | not persisted | **Future slice:** internal transfers and similar events. |

### 8.2 Audit and timestamps

**Rails timestamps:** `created_at` / `updated_at` on `operational_events`. Under §6.1, **do not** update rows after `status = posted`; `updated_at` therefore reflects pre-post changes only (or creation-only if updates are forbidden once inserted).

**Optional domain audit (defer unless required):** `created_by_id`, `request_id`, IP—introduce via a dedicated audit envelope ADR if compliance demands more than timestamps and operational logs.

---

## 9\. Integration role

Operational Events serve as:

* internal system-of-record for activity  
    
* integration boundary for external systems  
    
* trigger source for:  
    
  * posting  
  * notifications  
  * reporting projections  
  * compliance hooks

---

## 10\. Constraints

### 10.1 Required usage

The following MUST use Operational Events:

* teller transactions  
* account servicing actions  
* fee and interest processing  
* payment ingestion (ACH, wires, etc.)

### 10.2 Prohibited patterns

* direct balance mutation without event  
* direct GL posting without event  
* silent updates to financial records

---

## 11\. Consequences

### Positive

* unified transaction model  
* strong auditability  
* consistent reversal handling  
* easier integration  
* clear separation of business vs accounting logic

### Negative

* additional abstraction layer  
* requires disciplined event design  
* increased upfront modeling effort

---

## 12\. Related ADRs

* ADR-0001: Modular Monolith Architecture  
* ADR-0003: Posting & Journal Architecture  
* ADR-0010: Ledger persistence and seeded COA (MVP `operational_events` / `posting_batches` / `journal_entries` columns)

---

## 13\. Summary

The Operational Event Model becomes the **central backbone of BankCORE**, ensuring that:

* all actions are traceable  
* financial effects are consistently derived  
* the system remains auditable and extensible

All financial and operational workflows MUST pass through this model.