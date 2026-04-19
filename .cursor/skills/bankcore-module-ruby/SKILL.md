---
name: bankcore-module-ruby
description: Aligns Ruby and Rails code in bankcore-4 with docs/architecture/bankcore-module-catalog.md (app/domains, Core kernel, commands/queries, workspace controllers, dependency rules, single-owner tables). Use when implementing or refactoring domain code, migrations, routes, or tests for BankCORE; when adding features under Party, Accounts, Core::Posting, Teller, Integration, etc.; or when the user mentions the module catalog, modular monolith, operational events, posting, or ledger boundaries.
---

# BankCORE module-aligned Ruby

## Canonical spec

Before adding or changing domain behavior, read the relevant sections of the [module catalog](../../docs/architecture/bankcore-module-catalog.md) (domain map §3, per-module §6, controllers §7, naming §8, dependencies §9, table ownership §10). For a condensed checklist, see [reference.md](reference.md).

## Layout

- Put domain code under **`app/domains/<domain>/`** using the standard subfolders: `commands/`, `queries/`, `models/`, `services/`, `events/`, `policies/`, `validators/`, `value_objects/` (see catalog §5).
- **`Core::`** lives under `app/domains/core/` with subdomains `operational_events/`, `posting/`, `ledger/`, `business_date/` (catalog §4).
- Controllers stay **workspace-oriented** under `app/controllers/<workspace>/` (e.g. `teller/`, `ops/`), not nested as if they owned internal domains (catalog §7).

## Naming (catalog §8)

- **Modules:** short domain names — `Party`, `Accounts`, `Core::Posting` (not vague `Services` as an architectural root).
- **Commands:** imperative — `Accounts::Commands::OpenAccount`, `Core::Posting::Commands::PostEvent`.
- **Queries:** noun + intent — `Core::OperationalEvents::Queries::EventSearch`.
- **Services:** role-based — `PostingRuleResolver`, `BalanceProjector`.

## Dependency direction (catalog §9)

**Allowed:** controllers → commands / queries / orchestrators; commands → owned models and domain services; cross-domain only via explicit contracts (commands/events), not ad-hoc model reaches.

**Forbidden:** controllers building journal lines; teller (or any) code writing GL structures directly; reporting mutating operational write models; integrations mutating balances directly; deposits/loans creating financial effect without operational events + posting.

## Money movement

- Financial truth: **`Core::Posting`** + **`Core::Ledger`**. Durable business intent: **`Core::OperationalEvents`**.
- Do not duplicate “balance truth” in controllers or random service objects; keep invariants next to posting/ledger or explicit projectors the catalog allows.

## Database

- Each migration / model should respect **single table family ownership** (catalog §10). If a table is ambiguous, resolve ownership in an ADR before merging.
- Prefer adding columns and constraints in the **owning** domain’s migrations (or clearly named migration files) to preserve reviewability.

## Tests

- Prefer tests that pin **posting and ledger invariants** (balanced legs, immutability after commit, idempotency, reversal linkage) for any change that touches `Core::*` or money paths.

## When unsure

- Default to **smaller surface area** inside the correct domain; if the catalog does not name a home, propose an ADR under `docs/adr/` before inventing a new top-level namespace.
