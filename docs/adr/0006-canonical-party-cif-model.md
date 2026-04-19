# ADR-0006: Canonical Party (CIF) Model

**Status:** Accepted
**Date:** 2026-04-19
**Decision Type:** Core Domain Architecture
**Classification:** DROP-IN SAFE
**Suggested path:** `docs/adr/0006-canonical-party-cif-model.md`

---

## 1. Context

BankCORE requires a canonical Customer Information File (CIF) / Party model that supports the full spectrum of banking relationships without conflating identity, ownership, and account behavior.

A core banking system must support:

* individuals, organizations, trusts, estates, and government entities
* multiple parties per account and multiple accounts per party
* complex legal, fiduciary, and beneficial relationships
* reusable customer identity across all products and channels
* compliance, KYC/CIP, and audit requirements

Without a canonical Party model:

* identity becomes fragmented and duplicated
* ownership logic leaks into account and product code
* compliance becomes inconsistent and harder to audit
* downstream domains cannot reliably reuse customer data

---

## 2. Decision

BankCORE will implement a **canonical Party (CIF) model** where parties are the authoritative system-of-record for all persons and entities.

### 2.1 Core principle

> A party represents a real-world person or legal entity. Accounts, roles, and services reference parties; they do not redefine them.

### 2.2 Separation of concerns

The system MUST clearly separate:

* party identity
* party-to-party relationships
* party-to-account relationships
* contact methods
* compliance and identification artifacts

These MUST NOT be collapsed into a single "customer" record.

---

## 3. Canonical model

### 3.1 Party as primary entity

The Party domain is the authoritative identity layer.

Supported party types include:

* individual
* organization
* government
* trust
* estate

### 3.2 Independence from accounts

A party may exist without an account.

Examples:

* prospects
* beneficiaries
* authorized signers
* guarantors
* compliance subjects

### 3.3 Multiplicity

The model MUST support:

* one party → many accounts
* one account → many parties
* one party → many roles
* one party → many relationships to other parties

---

## 4. Party classification

### 4.1 High-level types

* `individual`
* `organization`
* `government`
* `trust`
* `estate`

### 4.2 Subtypes

Subtypes SHOULD be modeled separately, not as entirely different tables.

Examples:

* LLC, corporation, partnership
* revocable vs irrevocable trust
* nonprofit, municipality

---

## 5. Identity model

### 5.1 Individuals

* legal name components
* preferred/display name
* date of birth
* tax identifier references
* identity document references

### 5.2 Non-individuals

* legal name
* DBA/trade name
* formation identifiers
* tax identifiers
* jurisdiction

### 5.3 Naming rule

Search/display flexibility MUST NOT compromise legal identity accuracy.

---

## 6. Contact model

### 6.1 Separate records

Contact methods MUST be separate tables, not embedded fields.

### 6.2 Supported types

* addresses
* phone numbers
* email addresses

### 6.3 Purpose classification

Contact methods SHOULD support:

* primary
* mailing
* residential
* business
* notification
* statement delivery

### 6.4 Primary constraint

One primary per contact type SHOULD be supported.

---

## 7. Party-to-party relationships

### 7.1 Explicit modeling

Relationships MUST be explicit records.

Examples:

* spouse
* parent/child
* trustee-for
* POA-for
* beneficial-owner-of-entity

### 7.2 Structure

* relationship type
* source party
* target party
* effective dates
* status

### 7.3 Rule

Relationships MUST NOT be inferred from account co-ownership.

---

## 8. Party-to-account relationships

### 8.1 Separate domain concern

Ownership and role relationships MUST be separate from party identity.

### 8.2 Examples

* owner
* joint owner
* signer
* beneficiary
* trustee
* custodian

### 8.3 Reference

Detailed semantics defined in ADR-0007.

---

## 9. Compliance and identity artifacts

### 9.1 Separation

Compliance data MUST be linked but not embedded in party records.

### 9.2 Examples

* tax identifiers
* identity documents
* KYC/CIP status
* sanctions screening references

### 9.3 Auditability

All compliance artifacts SHOULD be auditable and time-aware.

---

## 10. Lifecycle

### 10.1 States

* prospect
* active
* restricted
* merged
* inactive

### 10.2 Merge rules

* merges MUST be controlled
* history MUST be preserved

---

## 11. Search and deduplication

### 11.1 Search

Support search by:

* name
* tax identifiers
* DOB/incorporation
* contact data
* account links

### 11.2 Deduplication

* probabilistic matching preferred
* manual review required before merge

---

## 12. Constraints

### 12.1 Required

* parties independent of accounts
* explicit relationships
* separate contact tables
* auditable merges

### 12.2 Prohibited

* account as customer record
* wide single-table customer model
* implicit relationship inference

---

## 13. Consequences

### Positive

* strong identity model
* reusable across domains
* improved compliance support
* clean ownership separation

### Negative

* increased complexity
* more onboarding steps

---

## 14. Implementation guidance

### Minimum

* party master table
* contact tables
* relationship tables
* merge workflow

### Expansion

* beneficial ownership
* segmentation
* communication preferences

---

## 15. Related ADRs

* ADR-0001
* ADR-0004
* ADR-0005
* ADR-0007

---

## 16. Summary

BankCORE adopts a **canonical Party (CIF) model** where:

* identity is independent and reusable
* relationships are explicit and auditable
* ownership is modeled separately

This provides a durable foundation for all customer, account, and compliance workflows.
