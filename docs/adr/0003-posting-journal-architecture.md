# ADR-0003: Posting & Journal Architecture

**Status:** Accepted **Date:** 2026-04-19 **Decision Type:** Core Financial Architecture **Classification:** DROP-IN SAFE

---

## 1\. Context

BankCORE must guarantee:

* strict double-entry accounting  
* real-time balance integrity  
* deterministic financial outcomes  
* complete auditability

While ADR-0002 defines *what happens* (Operational Events), BankCORE requires a formal model for *how financial impact is derived and recorded*.

Without a structured posting architecture:

* financial logic becomes duplicated across domains  
* GL mapping becomes inconsistent  
* balancing errors become possible  
* audit defensibility is weakened

---

## 2\. Decision

BankCORE will implement a **centralized Posting & Journal Architecture** consisting of:

1. **Posting Engine** (derivation layer)  
2. **Journal (Ledger)** (system of record)  
3. **Strict double-entry enforcement**

### 2.1 Core principle

All financial impact MUST be expressed as balanced journal entries derived from operational events.

---

## 3\. Posting pipeline

### 3.1 Canonical flow

1. Operational Event is created  
2. Posting Engine resolves posting rules  
3. Posting instructions are generated  
4. Batch is validated (must balance)  
5. Journal entries are persisted  
6. Downstream projections update balances

---

## 4\. Posting model

### 4.1 Core objects

#### PostingBatch

* groups all legs for a single event  
* atomic unit of posting

#### PostingLeg

* represents a single debit or credit  
    
* contains:  
    
  * account reference (GL or subledger)  
  * amount  
  * direction (debit/credit)

#### PostingRule

* defines how an event maps to posting legs  
* resolved via Product \+ Event Type

---

## 5\. Double-entry enforcement

### 5.1 Rule

Every posting batch MUST satisfy:

* total debits \== total credits

### 5.2 Validation

* enforced before persistence  
* failure results in transaction rollback

### 5.3 No exceptions

* no single-sided entries  
* no “temporary imbalance” states

---

## 6\. Journal model

### 6.1 JournalEntry

Represents a posted accounting entry.

Fields:

* posting\_batch\_id  
* business\_date  
* effective\_at  
* event\_id

### 6.2 JournalLine

Represents individual debit/credit lines.

Fields:

* journal\_entry\_id  
* gl\_account\_id  
* amount\_cents  
* debit/credit indicator

---

## 7\. GL mapping

### 7.1 Source

GL mapping is derived from:

* product configuration  
* event type

### 7.2 Rule

Posting Engine MUST NOT hardcode GL accounts.

### 7.3 Resolver

Use:

* `GlMappingResolver`  
* `PostingRuleResolver`

---

## 8\. Reversals

### 8.1 Rule

Financial corrections MUST be performed via reversal postings.

### 8.2 Behavior

* reversal creates a new posting batch  
* all legs are inverted  
* linked to original event

---

## 9\. Balance derivation

### 9.1 Source of truth

Balances are derived from:

* journal entries (authoritative)

### 9.2 Projections

For performance, maintain:

* account balance projections  
* daily snapshots

### 9.3 Rule

Projections MUST be:

* rebuildable from journal  
* never treated as source of truth

---

## 10\. Constraints

### 10.1 Required usage

The following MUST go through Posting Engine:

* deposits  
* withdrawals  
* transfers  
* fees  
* interest  
* loan payments  
* reversals

### 10.2 Prohibited patterns

* direct balance updates  
* direct GL inserts from controllers  
* bypassing posting for “simple” transactions

---

## 11\. Consequences

### Positive

* guaranteed financial integrity  
* consistent accounting behavior  
* strong audit trail  
* centralized logic

### Negative

* additional abstraction layer  
* requires upfront modeling of posting rules

---

## 12\. Related ADRs

* ADR-0001: Modular Monolith Architecture  
* ADR-0002: Operational Event Model  
* ADR-0010: Ledger persistence, balancing triggers, and seeded COA (MVP relational shape)

---

## 13\. Summary

The Posting & Journal Architecture establishes the **financial backbone of BankCORE**.

* Operational Events define intent  
* Posting Engine defines financial impact  
* Journal defines immutable financial truth

All monetary effects MUST pass through this pipeline.  