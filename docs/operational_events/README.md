# Operational event specs

This directory holds **per–`event_type` specifications**: semantics, persistence, posting, idempotency, reversals, and cross-links to ADRs. They are the working source for implementers and tests; [ADR-0002](../adr/0002-operational-event-model.md) remains the cross-cutting model.

## Filename convention

- Files use **kebab-case**: `deposit-accepted.md` documents `event_type` **`deposit.accepted`** (dots in the type string, not in the filename).
- One primary `event_type` per document. Patterns that span types (e.g. compensating reversal) live in a dedicated spec.

## Spec format (use for every new doc)

Each spec uses the same headings so scans and diffs stay predictable:

| Section | Purpose |
| ------- | ------- |
| **Summary** | One short paragraph: what business fact this row records. |
| **Registry** | Canonical `event_type` string, category (financial / servicing / operational), MVP phase note. |
| **Semantics** | Preconditions, postconditions, what must never happen. |
| **Persistence** | Required and optional columns / FKs on `operational_events` (and related tables if this type owns rows elsewhere). |
| **Lifecycle** | `pending` → `posted` (and any other allowed values); meaning of `posted` for non–GL-backed types. |
| **Posting** | Whether `PostEvent` runs; GL accounts and legs at a high level; subledger (`deposit_account_id` on lines) if applicable. |
| **Idempotency** | `(channel, idempotency_key)` rules; which fields participate in the **fingerprint** for mismatch detection. |
| **Reversals** | Whether this type can be reversed, by what compensating type, supervisor gate if any. |
| **Relationships** | `teller_session_id`, `source_account_id`, `destination_account_id`, links to `holds`, etc. |
| **Module ownership** | Which `app/domains/**` module owns validation and commands (per [module catalog](../architecture/bankcore-module-catalog.md)). |
| **References** | ADRs and related specs. |
| **Examples** | Minimal JSON or pseudo-payload + posting sketch. |

Copy the structure from any existing file in this folder when adding a new `event_type`, or start from [_template.md](_template.md).

## Index

| Spec | `event_type` | GL posting | Record command |
| ---- | ------------ | ---------- | ---------------- |
| [deposit-accepted.md](deposit-accepted.md) | `deposit.accepted` | Yes | `RecordEvent` |
| [withdrawal-posted.md](withdrawal-posted.md) | `withdrawal.posted` | Yes | `RecordEvent` |
| [transfer-completed.md](transfer-completed.md) | `transfer.completed` | Yes | `RecordEvent` |
| [compensating-reversal.md](compensating-reversal.md) | `posting.reversal` | Yes | `RecordReversal` |
| [hold-placed.md](hold-placed.md) | `hold.placed` | No | `Accounts::Commands::PlaceHold` |
| [hold-released.md](hold-released.md) | `hold.released` | No | `Accounts::Commands::ReleaseHold` |
| [teller-session-opened.md](teller-session-opened.md) | (table-first MVP; OE optional) | No | `Teller::Commands::OpenSession` |
| [teller-session-closed.md](teller-session-closed.md) | (table-first MVP; OE optional) | No | `Teller::Commands::CloseSession` |
| [override-requested.md](override-requested.md) | `override.requested` | No | `RecordControlEvent` |
| [override-approved.md](override-approved.md) | `override.approved` | No | `RecordControlEvent` |
| [fee-assessed.md](fee-assessed.md) | `fee.assessed` | Yes | `RecordEvent` |
| [fee-waived.md](fee-waived.md) | `fee.waived` | Yes | `RecordEvent` |
| [teller-drawer-variance-posted.md](teller-drawer-variance-posted.md) | `teller.drawer.variance.posted` | Yes (optional flag) | `RecordEvent` (`system` only; see [ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)) |

**Teller JSON routes (workspace):** `POST /teller/operational_events`, `POST /teller/operational_events/:id/post`, `POST /teller/reversals`, `POST /teller/holds` (optional **`placed_for_operational_event_id`** on `hold` per [hold-placed.md](hold-placed.md) / [ADR-0013](../adr/0013-holds-available-and-servicing-events.md) §3), `POST /teller/holds/release`, `POST /teller/teller_sessions`, `POST /teller/teller_sessions/close`, `POST /teller/teller_sessions/approve_variance`, `POST /teller/overrides`, **`GET /teller/event_types`** ([ADR-0019](../adr/0019-event-catalog-and-fee-events.md)), **`GET /teller/operational_events`** ([ADR-0017](../adr/0017-deposit-products-fk-narrow-scope.md) §2.5), **`GET /teller/reports/trial_balance`**, **`GET /teller/reports/eod_readiness`** ([ADR-0016](../adr/0016-trial-balance-and-eod-readiness.md)) — see [config/routes.rb](../../config/routes.rb).

**Request identity:** every teller workspace request (**including report `GET`s**) must include header **`X-Operator-Id`** with the id of an active row in **`operators`** (see [ADR-0015](../adr/0015-teller-workspace-authentication.md)). **`POST /teller/reversals`**, **`override.approved`** on `POST /teller/overrides`, and **`POST /teller/teller_sessions/approve_variance`** require a **supervisor** operator; role is enforced from the database, not from client-supplied role headers.

**Teller cash and drawer:** when **`TELLER_REQUIRE_OPEN_SESSION_FOR_CASH`** is enabled (default **true**), **`channel: teller`** **`deposit.accepted`** and **`withdrawal.posted`** on **`POST /teller/operational_events`** must include **`teller_session_id`** for an **open** session ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)). **`transfer.completed`** is exempt.

**Drawer variance to GL (optional):** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is enabled, **`CloseSession`** / **`ApproveSessionVariance`** create and post **`teller.drawer.variance.posted`** (`system` channel) for non-zero variance ([ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)). This type is **not** accepted via **`POST /teller/operational_events`** from operators.

## Concept layering

[Concept 101](../concepts/101-operational_event_enums_concept.md) parent/component vocabulary is **analytical**; it does not replace the `event_type` strings in this folder. Mapping from `event_type` → concept 101 belongs in documentation or a future mapping table, per ADR-0002 §2.2.

## Domain mapping

These specs describe **MVP / Phase 1** branch-teller behavior per [01-mvp-vs-core.md](../concepts/01-mvp-vs-core.md) and [roadmap.md](../roadmap.md). Owning modules are called out in each spec; the financial kernel remains `Core::OperationalEvents`, `Core::Posting`, and `Core::Ledger`.
