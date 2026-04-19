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

---

## 3\. Event lifecycle

### 3.1 Standard flow

1. Event is **created** (Operational Event recorded)  
2. Event is **validated/classified**  
3. Event is **posted** (via Posting Engine)  
4. Event produces **journal entries**  
5. Event becomes part of **immutable history**

---

## 4\. Event structure

Each operational event MUST include:

### 4.1 Core fields

* `event_type` (enum, canonical registry)  
* `status` (pending, posted, reversed)  
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

### 7.1 Mechanism

* unique `idempotency_key`  
* duplicate detection at event creation layer

### 7.2 Outcome

* duplicate submissions do not create duplicate financial impact

---

## 8\. Integration role

Operational Events serve as:

* internal system-of-record for activity  
    
* integration boundary for external systems  
    
* trigger source for:  
    
  * posting  
  * notifications  
  * reporting projections  
  * compliance hooks

---

## 9\. Constraints

### 9.1 Required usage

The following MUST use Operational Events:

* teller transactions  
* account servicing actions  
* fee and interest processing  
* payment ingestion (ACH, wires, etc.)

### 9.2 Prohibited patterns

* direct balance mutation without event  
* direct GL posting without event  
* silent updates to financial records

---

## 10\. Consequences

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

## 11\. Related ADRs

* ADR-0001: Modular Monolith Architecture  
* ADR-0003: Posting & Journal Architecture (future)

---

## 12\. Summary

The Operational Event Model becomes the **central backbone of BankCORE**, ensuring that:

* all actions are traceable  
* financial effects are consistently derived  
* the system remains auditable and extensible

All financial and operational workflows MUST pass through this model.