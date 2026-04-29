# ADR-0034: Admin organization and cash maintenance

**Status:** Accepted - first slice implemented  
**Date:** 2026-04-29  
**Decision Type:** Admin configuration / branch operations reference data  
**Aligns with:** [ADR-0031](0031-cash-inventory-and-management.md), [ADR-0032](0032-operating-units-and-branch-scope.md), [ADR-0033](0033-admin-rbac-maintenance.md), [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Context and Problem Statement

BankCORE now has first-class operating units for organizational scope and Cash-domain locations for custody points such as branch vaults, teller drawers, and internal transit locations. Admin staff need an internal HTML surface to maintain that reference data without weakening cash custody controls or turning operating units into accounting entities.

---

## 2. Decision Outcome

BankCORE will add Admin HTML maintenance for:

- Organization-owned `operating_units`
- Cash-owned `cash_locations`

The Admin controllers will orchestrate domain commands and queries. Organization and Cash remain the table owners and enforce lifecycle rules.

This slice uses `system.configure` as the required admin capability.

---

## 3. Invariants

- Operating units are operational scope only. They are not ledgers, legal entities, or business-date partitions.
- Operating units and cash locations are never deleted through the Admin UI.
- Seeded default operating-unit codes `BANKCORE` and `MAIN` must not be changed through Admin maintenance.
- Cash locations must not move between operating units after creation. Cash custody changes use cash movements, counts, and balances, not metadata edits.
- A cash location may be deactivated only when it has zero cash balance, no open teller session, no pending cash movement, and no pending cash variance.
- An operating unit may be closed only when it has no active child operating units and no active cash locations.
- Cash-location creation continues to use `Cash::Commands::CreateLocation` so zero-balance creation and active vault/drawer uniqueness remain centralized.

---

## 4. Audit Boundary

This slice follows ADR-0033 and relies on standard `created_at` / `updated_at` timestamps as lightweight change evidence. It does not introduce a dedicated admin audit table or new operational event types.

---

## 5. Consequences

- Admin users can configure operating-unit hierarchy and Cash custody locations without direct database edits.
- Cash location status transitions are conservative and block unsafe deactivation while balances, sessions, or pending approvals remain.
- The implementation keeps reference-data maintenance separate from monetary truth in Core posting and ledger.
