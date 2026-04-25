# ADR-0005: Product Configuration Framework

**Status:** Accepted 
**Date:** 2026-04-19 
**Decision Type:** Core Domain Architecture 

---

## 1\. Context

BankCORE must support multiple deposit and loan products with differing behavior (interest, fees, limits, overdraft, statements, GL mappings) without embedding rules directly in code paths.

Without a formal product framework:

* behavior becomes hardcoded and duplicated  
* changes require code deploys  
* inconsistencies emerge across channels  
* auditability of product behavior is reduced

---

## 2\. Decision

BankCORE will implement a **parameter-driven Product Configuration Framework** where product definitions and their behavioral rules are stored as data and resolved at runtime.

### 2.1 Core principle

All account behavior MUST be derived from product configuration, not hardcoded logic.

---

## 3\. Product model

### 3.1 Product types

* Deposit products (DDA, Savings, MMA, CDA)  
* Loan products (installment, revolving, mortgage, etc.)

### 3.2 Core product attributes

* `product_code`  
* `product_type`  
* `status` (active, inactive)  
* `currency`  
* `gl_mapping_profile_id`  
* `interest_profile_id` (optional)  
* `fee_profile_id` (optional)  
* `limit_profile_id` (optional)  
* `overdraft_profile_id` (optional)  
* `statement_profile_id` (optional)

---

## 4\. Behavior profiles

Behavior is decomposed into reusable profiles referenced by products.

### 4.1 Interest profile

Defines:

* rate type (fixed, tiered, indexed)  
* compounding method  
* day-count convention  
* accrual frequency  
* posting frequency

### 4.2 Fee profile

Defines:

* fee types (monthly, overdraft, service, transaction)  
* triggers and schedules  
* waiver rules

### 4.3 Limit profile

Defines:

* transaction limits (amount, velocity)  
* channel constraints

### 4.4 Overdraft profile

Defines:

* eligibility  
* fee linkage  
* posting/authorization behavior

### 4.5 Statement profile

Defines:

* cycle frequency  
* cutoff rules

### 4.6 GL mapping profile

Defines mapping from event types to GL accounts used by the Posting Engine.

---

## 5\. Resolution model

### 5.1 Runtime resolution

At execution time, services resolve behavior via:

* `ProductResolver`  
* `InterestRuleResolver`  
* `FeeRuleResolver`  
* `LimitEvaluator`  
* `GlMappingResolver`

### 5.2 Rule

No domain should infer behavior directly from product codes without using resolvers.

---

## 6\. Event interaction

Product configuration drives how events are interpreted and posted.

Examples:

* `fee.assessed` → fee profile determines amount and eligibility  
* `interest.accrued` → interest profile determines calculation  
* `deposit.accepted` → GL mapping profile determines posting legs

---

## 7\. Versioning and change control

### 7.1 Rule

Product configurations MUST be versioned or otherwise auditable.

### 7.2 Behavior

* changes should not retroactively alter historical calculations  
* effective dating SHOULD be supported where needed

---

## 8\. Constraints

### 8.1 Required rules

* products must be data-driven  
* behavior must be resolved through profiles/resolvers  
* GL mapping must come from configuration

### 8.2 Prohibited patterns

* hardcoding interest/fee logic in controllers or commands  
* embedding GL accounts directly in posting code  
* using product codes as logic switches without resolver abstraction

---

## 9\. Consequences

### Positive

* high configurability  
* reduced code duplication  
* consistent behavior across channels  
* improved auditability

### Negative

* increased data model complexity  
* requires strong validation of configuration  
* introduces resolver layer overhead

---

## 10\. Implementation guidance

### 10.1 Minimum implementation

* deposit products  
* GL mapping profile  
* basic fee profile  
* simple interest profile (optional initially)

### 10.2 Expansion path

* tiered and indexed rates  
* complex fee waivers  
* product-specific balance-basis rules  
* promotional and time-bound configurations

### 10.3 Phase 4.3 resolver baseline

Phase 4.3 implements a narrow resolver baseline without completing the full profile framework:

* `Products::Services::DepositProductResolver` exposes a stable per-product behavior contract for existing deposit behavior: monthly maintenance fee rule, deny-NSF overdraft policy, and monthly statement profile.
* `Products::Services::EffectiveDatedResolver` centralizes active-on-date resolution: `status = active`, `effective_on <= as_of`, and `ended_on IS NULL OR ended_on >= as_of`.
* Singular behavior families such as monthly maintenance rules, deny-NSF policies, and monthly statement profiles reject overlapping active windows at the model-validation layer.
* Per-product GL mapping, reusable profile catalogs, product version migration, admin workflows, interest profile depth, and limit profile depth remain deferred until a selected channel or product requirement needs them.

---

## 11\. Related ADRs

* ADR-0001: Modular Monolith Architecture  
* ADR-0002: Operational Event Model  
* ADR-0003: Posting & Journal Architecture  
* ADR-0004: Account & Balance Model

---

## 12\. Summary

BankCORE adopts a **product-driven configuration model** where:

* products define behavior via composable profiles  
* runtime resolvers apply rules consistently  
* posting, fees, and interest derive from configuration

This enables flexibility, consistency, and auditability across all banking operations.