# ADR-0009: Initial Party persistence schema

**Status:** Proposed  
**Date:** 2026-04-21  
**Decision Type:** Domain data model (Party)  
**Aligns with:** [ADR-0006](0006-canonical-party-cif-model.md) (canonical CIF concepts), [docs/architecture/bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md) §6.5 (Party owns `party_*` tables)

---

## 1. Context

[ADR-0006](0006-canonical-party-cif-model.md) defines the **conceptual** Party model (types, separation of identity vs relationships vs party-to-account links). It does not prescribe concrete tables.

We need an **initial relational shape** for MVP and vertical-slice work so migrations and `Party` module code can proceed without overloading ADR-0006 or conflating identity storage with [ADR-0007](0007-party-account-ownership.md) (party-to-account roles).

---

## 2. Decision

### 2.1 Scope

* **In scope:** `party_records` master row (maps to `Party::Models::PartyRecord` in the module catalog) plus **individual** and **organization** subtype profile tables, aligned with ADR-0006 §3–5 and §4.2 (subtypes in separate structures).
* **Out of scope for this ADR’s tables:** `government`, `trust`, and `estate` subtype profile tables (see §2.7)—those party types may still have `party_records` rows with `party_type` set until subprofile tables exist. Contact, relationship, and tax or compliance artifact tables remain per ADR-0006 §6–9 (separate follow-on migrations).
* **Not in this ADR:** party-to-account participation (that is [ADR-0007](0007-party-account-ownership.md)).

### 2.2 Enumerations (documentation only)

Where **Notes** (or equivalent) lists a **closed set of string values** for a column (e.g. `party_type`, `org_kind`), treat that set as the **canonical application enum**. **Initial migrations do not add** PostgreSQL enum types or `CHECK` constraints for these columns; validation and transitions live in the Party domain until we deliberately add database-level constraints.

### 2.3 Master table: `party_records`

| Column        | Type     | Constraints   | Notes |
| ------------- | -------- | ------------- | ----- |
| `id`          | bigint   | PK            | |
| `name`        | string   | `null: false` | **Derived** from the active subtype profile (rules below); denormalized for search and list UIs; must be recomputed in the same command transaction as any profile field that affects it. |
| `party_type`  | string   | `null: false` | `individual` \| `organization` \| `government` \| `trust` \| `estate` (ADR-0006 §4.1). |
| `created_at`  | datetime |               | |
| `updated_at`  | datetime |               | |

#### Derivation of `party_records.name`

There is no separate `party_profiles` table; `party_records.name` is the canonical display string built from the relevant subprofile.

* **`individual`** (from `party_individual_profiles`): join `first_name`, optional `middle_name` (include only if non-blank), and `last_name` with **single spaces** between segments—no duplicate or leading/trailing spaces. If `name_suffix` is non-blank, append **`, {name_suffix}`** (comma, space, suffix). Example shape: `Jane Marie Doe, Jr.` Do **not** use `preferred_first_name` / `preferred_last_name` for `party_records.name` (those remain for channel-specific display until a separate column or ADR says otherwise).
* **`organization`** (from `party_organization_profiles`): **`{legal_name}`**. If `dba_name` is non-blank, append **` (d/b/a {dba_name})`** (space, parenthetical). Example: `Acme Holdings LLC (d/b/a Acme Bank)`.
* **`government` \| `trust` \| `estate`:** no subprofile tables in this ADR yet (§2.7); **`name` is supplied and maintained by Party commands** until those profiles exist, then this section should be extended with the same “derive on every profile write” rule.

### 2.4 Subtype: `party_individual_profiles`

One row per party record whose parent `party_records.party_type` is `individual` (enforce in application or partial unique index on `party_record_id`).

| Column                  | Type     | Constraints                          | Notes |
| ----------------------- | -------- | ------------------------------------ | ----- |
| `id`                    | bigint   | PK                                   | |
| `party_record_id`       | bigint   | FK → `party_records`, `null: false`  | Unique per party record for v1. |
| `first_name`            | string   | `null: false`                        | |
| `middle_name`           | string   | nullable                             | |
| `last_name`             | string   | `null: false`                        | |
| `name_suffix`           | string   | nullable                             | |
| `preferred_first_name`  | string   | nullable                             | |
| `preferred_last_name`   | string   | nullable                             | |
| `date_of_birth`         | date     | nullable                             | |
| `occupation`            | string   | nullable                             | |
| `employer`              | string   | nullable                             | |
| `created_at`            | datetime |                                      | |
| `updated_at`            | datetime |                                      | |

### 2.5 Subtype: `party_organization_profiles`

One row per party record whose parent `party_records.party_type` is `organization` (same uniqueness pattern as individual).

| Column                     | Type     | Constraints                   | Notes |
| -------------------------- | -------- | ----------------------------- | ----- |
| `id`                       | bigint   | PK                            | |
| `party_record_id`          | bigint   | FK → `party_records`, `null: false` | Unique per party record for v1. |
| `org_kind`                 | string   | nullable                      | `corp_c` \| `corp_s` \| `llc_corp_c` \| `llc_corp_s` \| `llc_disregarded` \| `llc_partnership` \| `partnership` \| `sole_proprietor` (ADR-0006 §4.2 style; optional until org classification is required). |
| `legal_name`               | string   | `null: false`                 | |
| `dba_name`                 | string   | nullable                      | |
| `date_of_formation`        | date     | nullable                      | |
| `formation_country_code`   | string   | `null: false` preferred for orgs | **ISO 3166-1 alpha-2** (two characters). Validate against [docs/reference/iso-3166-1-country-codes.csv](../reference/iso-3166-1-country-codes.csv) at application boundary. |
| `formation_region_code`    | string   | nullable                      | When present, stores the **full ISO 3166-2** code for the principal subdivision (e.g. `US-CA`), not a local subcode alone. Validate against [docs/reference/iso-3166-2-region-codes.CSV](../reference/iso-3166-2-region-codes.CSV); `formation_country_code` must match the country prefix of this value. |
| `created_at`               | datetime |                               | |
| `updated_at`               | datetime |                               | |

### 2.6 Naming and module ownership

* Tables use the **`party_*`** prefix family (`party_records`, `party_organization_profiles`, …) and are owned by the **Party** module per [catalog §10](../architecture/bankcore-module-catalog.md).
* The master row maps to **`Party::Models::PartyRecord`**; Ruby models should follow the same namespacing as the rest of `app/domains/party` when implemented.
* Workspace routes may still expose **`resources :parties`** (human-facing “party”); the **persisted** aggregate root table remains **`party_records`**.

### 2.7 Future subtype profile tables

Subprofile persistence for **`government`**, **`trust`**, and **`estate`** party types is **future development**. When added, follow the same pattern as `party_individual_profiles` / `party_organization_profiles` (one optional row per party of that type). Table names should stay on the same **`party_<subtype>_profiles`** convention as the individual and organization tables, for example:

* `party_government_profiles`
* `party_trust_profiles`
* `party_estate_profiles`

(Schema for those tables is intentionally unspecified here.)

---

## 3. Consequences

**Positive:** Clear home for first migrations; subtype separation matches ADR-0006; ISO reference files in-repo give a single validation source; tax identifiers and filing numbers are deferred to dedicated compliance or artifact models per ADR-0006 §9.

**Negative:** `party_records.name` denormalization requires discipline on every profile update command.

**Neutral:** Other party types and party-to-account links are documented in other ADRs; this ADR may be **superseded or extended** when additional subtypes, DB enum constraints, or vault-linked identifiers land.

---

## 4. Related ADRs

* [ADR-0006](0006-canonical-party-cif-model.md) — conceptual model this schema implements.
* [ADR-0007](0007-party-account-ownership.md) — account participation (not party row layout).
