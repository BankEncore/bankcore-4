# ADR-0025: Internal workspace HTML UI

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [module catalog](../architecture/bankcore-module-catalog.md) §7, [ADR-0015](0015-teller-workspace-authentication.md), [ADR-0037](0037-internal-staff-authorized-surfaces.md), [roadmap](../roadmap.md) Phase 3.5

---

## 1. Context

BankCORE has a JSON teller workspace for branch operations, reporting reads, and supervisor controls. Phase 3 added product and financial depth, but the shipped surfaces remain API/curl oriented.

Phase 3.5 adds internal Rails-rendered HTML workspaces for branch, operations, and product configuration users. This is an internal user-experience layer over existing domain commands and queries, not a new customer or partner channel.

---

## 2. Decision

Use a hybrid workspace architecture:

- Existing JSON APIs, including `/teller/*` and `X-Operator-Id`, remain stable.
- New internal HTML screens use Rails server-rendered views with the existing Rails asset stack.
- HTML controllers are organized by workspace, not domain ownership.
- Controllers validate and normalize input, call domain commands/queries/orchestrators, and prepare response/view state.
- Controllers must never construct journal lines, embed posting rules, or implement balance math.

The `branch` workspace may expose **multiple authorized surfaces** (capability-gated navigation lanes or controller groups) for the same HTML namespace—for example **teller line**, **teller supervisor**, and **CSR**—without splitting domain modules. See [ADR-0037](0037-internal-staff-authorized-surfaces.md).

---

## 3. Workspace namespaces

Phase 3.5 uses these internal HTML workspace namespaces:

| Namespace | Purpose |
| --- | --- |
| `branch` | Branch-local internal workspace. First screens wrap teller session and transaction workflows, but the namespace leaves room for broader branch operations. |
| `ops` | Centralized operations workspace. **Close package** (`/ops/close_package`) is the primary **EOD hub** (readiness, derived classification, trial balance, guarded business-date close). Legacy screens **EOD readiness** (`/ops/eod`, trial-balance-focused) and **business date close** (`/ops/business_date_close`) remain; close POST redirects back to Close package. Also: operational event search/detail and exception review. |
| `admin` | Product/configuration workspace for product rules and other internal configuration surfaces. |

A shared internal base controller/layout may live under `internal` if useful for authentication, navigation, flash, current business date, and role-aware links. Concrete feature routes should still remain under `branch`, `ops`, or `admin`.

The existing JSON `/teller` namespace is not renamed or repurposed in this phase.

---

## 4. Authentication and roles

Internal HTML workspaces use session-cookie authentication backed by `Workspace::Models::Operator`.

The first implementation should store `operator_id` in the Rails session, load the active operator from the database on each request, and reject missing, unknown, or inactive operators. This is an internal staff trust boundary only; it must not be reused for future customer portal, partner API, or fintech API authentication.

Role posture for first slices:

- Reuse existing `teller` and `supervisor` roles.
- Preserve existing supervisor gates for reversals, override approval, teller session variance approval, and business date close.
- Use supervisor as the initial fallback for read-only `ops` and `admin` screens until distinct `operations` or `admin` roles are justified by a mutating screen.
- Do not trust role values from request params, headers, or forms.

ADR-0015 remains authoritative for the existing JSON teller workspace. This ADR only adds browser-session posture for internal HTML workspaces.

---

## 5. Workorder sequence

Phase 3.5 should proceed as reviewable workorders:

1. **WO1 documentation**: this ADR, roadmap notes, and contributor guidance.
2. **WO2 shell/auth**: shared internal layout, session-backed operator auth, navigation, current business date, flash, and role-aware links.
3. **WO3 branch session UI**: branch dashboard, open/close teller session, and supervisor variance approval.
4. **WO4 ops EOD/event UI**: Close package as canonical EOD workspace; legacy EOD readiness and standalone close preview; trial balance; operational event search and event detail views.
5. **WO5 admin product read-only UI**: product, fee-rule, overdraft-policy, and statement-profile inspection.
6. **WO6 branch transaction forms**: deposit, withdrawal, transfer, holds, posting, and reversal forms over existing commands.
7. **WO7 admin/ops controls**: guarded product config edits, engine runs, exception queues, and close-package/EOD hardening (classification, redirects, dashboard entry points).

WO3, WO4, and WO5 may be planned independently after WO2 establishes shared auth and layout conventions.

---

## 6. Non-goals

- Customer portal, customer authentication, customer-safe redaction, or self-service workflows.
- Partner, fintech, ACH, wire, card, or ATM APIs.
- Replacing or renaming existing JSON `/teller` routes.
- New event types, posting semantics, GL mappings, or balance models.
- Product resolver overhaul.
- Product configuration writes in WO1.
- Statement PDF/document rendering.

---

## 7. Consequences

- Internal UI work can progress without destabilizing existing JSON tests and curl workflows.
- `branch` avoids overloading `teller`, which already refers to a role and an existing JSON namespace.
- Browser auth has a clear internal-only boundary and can evolve separately from future customer or partner channels.
- Later mutating screens must add role gates, confirmations, audit attribution, and tests before exposing commands.
