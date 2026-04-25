# ADR-0001: Modular Monolith Architecture with Domain Boundaries

**Status:** Accepted 
**Date:** 2026-04-19 
**Decision Type:** Foundational Architecture 
**Supersedes:** None 
**Superseded by:** N/A

---

## 1\. Context

BankCORE is being designed as a production-grade core banking system with strict requirements for:

* financial correctness (double-entry integrity)  
* auditability (immutable financial history)  
* operational control (approvals, reversals, supervision)  
* extensibility (future products, channels, integrations)

Early architectural decisions must avoid two common failure modes:

1. **Monolithic sprawl** (no boundaries, high coupling)  
2. **Premature microservices** (fragmented financial logic, loss of consistency)

The system must support:

* teller and branch operations (roadmap Phase 1)  
* operational hardening (roadmap Phase 2)  
* product and financial depth (roadmap Phase 3)  
* channels and ecosystem integrations (roadmap Phase 4)  
* regulatory and audit requirements

A clear architectural foundation is required before further domain expansion.

---

## 2\. Decision

BankCORE will be implemented as a **modular monolith** using a single Rails application with strict internal domain boundaries.

### 2.1 Architectural model

* One primary Rails application  
* One primary database (initially)  
* Domain-based modularization under `app/domains/`  
* Workspace-based controllers under `app/controllers/`  
* Explicit command/query/service patterns  
* Domain events as internal contracts

### 2.2 Financial kernel centralization

The following domains constitute the **financial kernel** and MUST remain tightly coupled and centrally governed:

* `Core::OperationalEvents`  
* `Core::Posting`  
* `Core::Ledger`  
* `Core::BusinessDate`

These domains:

* define financial truth  
* enforce double-entry integrity  
* govern business date and posting rules  
* must not be distributed prematurely

### 2.3 Domain boundary model

All application logic will be organized into bounded domains under `app/domains/`.

Primary domain groups:

* Financial kernel  
* Customer and contract domains  
* Servicing domains  
* Operational domains  
* Control and support domains

Each domain:

* owns its data (table ownership)  
* exposes commands and queries  
* encapsulates business rules  
* communicates via explicit interfaces or events

### 2.4 Engines policy

Rails engines will NOT be used for core financial domains.

Engines MAY be introduced for:

* API gateway  
* customer portal  
* reporting portal  
* admin console

Engines MUST NOT be used for:

* posting engine  
* ledger  
* business date  
* operational events  
* account core

---

## 3\. Detailed rules

### 3.1 Command/query separation

* All state changes occur through **commands**  
* All reads occur through **queries**  
* Controllers MUST NOT contain business logic

### 3.2 Event-driven internal contracts

All material financial actions MUST:

1. Create an operational event  
2. Be processed through the posting engine  
3. Result in journal entries

No module may bypass this flow for balance-affecting operations.

### 3.3 Table ownership

Each table MUST have a single owning domain.

Cross-domain writes MUST occur via:

* commands  
* domain services  
* posting/event pipelines

### 3.4 Dependency direction

Allowed:

* controllers → commands/queries  
* commands → domain services  
* services → owned models

Forbidden:

* controllers writing ledger entries  
* teller flows bypassing posting  
* reporting writing operational data  
* integrations mutating balances directly

### 3.5 Immutability requirements

* Financial history MUST be append-only  
* Corrections MUST be modeled as reversals  
* No destructive edits to posted financial records

---

## 4\. Consequences

### 4.1 Positive

* Strong financial integrity  
* Clear ownership boundaries  
* Improved testability  
* Easier reasoning about system behavior  
* Reduced risk of inconsistent balances  
* Controlled path to future modularization

### 4.2 Negative

* Requires discipline in enforcing boundaries  
* Larger initial codebase within one application  
* Some duplication of patterns across domains  
* Requires explicit contracts rather than implicit coupling

---

## 5\. Alternatives considered

### 5.1 Fully monolithic (no domain boundaries)

Rejected because:

* leads to uncontrolled coupling  
* difficult to scale or reason about  
* high regression risk

### 5.2 Microservices-first architecture

Rejected because:

* introduces distributed consistency problems  
* complicates financial integrity guarantees  
* increases operational overhead  
* premature for early-stage system

### 5.3 Engine-per-domain architecture

Rejected because:

* Rails engines introduce unnecessary isolation overhead  
* financial domains are too tightly coupled for early separation

---

## 6\. Roadmap-aligned migration path

Future evolution follows the roadmap phase labels while preserving the modular-monolith decision in this ADR:

### Phase 1 — Branch-safe MVP core

* Establish the modular monolith, domain boundaries, and centralized financial kernel.
* Prove branch-safe money movement through operational events, posting, ledger, teller sessions, and reversals.

### Phase 2 — Operational hardening

* Harden the same modular monolith with product FKs, event catalog metadata, observability reads, business-date close, and drawer-variance controls.
* Keep operational hardening inside explicit domain boundaries rather than extracting core financial domains.

### Phase 3 — Product and financial depth

* Add deeper product and financial slices behind domain commands, queries, and operational-event/posting contracts.
* Keep posting, ledger, business date, and operational events centralized.

### Phase 4 — Channels and ecosystem

* Add customer, partner, and integration channels over stable domain contracts.
* Edge extraction for APIs, reporting, ingestion, channels, or analytics may be considered only when operationally justified; it is not implied by the roadmap phase number.

The financial kernel remains centralized until strong justification exists. Any future distributed architecture remains optional and must preserve stable domain contracts.

---

## 7\. Related documents

* `docs/architecture/bankcore-module-catalog.md`  
    
* Future ADRs:  
    
  * Posting architecture  
  * Event model  
  * Product configuration model  
  * CIF model

---

## 8\. Summary

BankCORE adopts a **modular monolith architecture** to balance:

* financial safety  
* implementation practicality  
* long-term scalability

The system is organized around domain boundaries, with a centralized financial kernel and controlled extension points.

This decision establishes the foundational structure for all subsequent architectural and implementation work.  