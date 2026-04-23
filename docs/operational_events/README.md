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

**Teller JSON routes (workspace):** `POST /teller/operational_events`, `POST /teller/operational_events/:id/post`, `POST /teller/reversals`, `POST /teller/holds`, `POST /teller/holds/release`, `POST /teller/teller_sessions`, `POST /teller/teller_sessions/close`, `POST /teller/overrides` (see [config/routes.rb](../../config/routes.rb)).

## Concept layering

[Concept 101](../concepts/101-operational_event_enums_concept.md) parent/component vocabulary is **analytical**; it does not replace the `event_type` strings in this folder. Mapping from `event_type` → concept 101 belongs in documentation or a future mapping table, per ADR-0002 §2.2.

## Domain mapping

These specs describe **MVP / Phase 1** branch-teller behavior per [01-mvp-vs-core.md](../concepts/01-mvp-vs-core.md) and [roadmap.md](../roadmap.md). Owning modules are called out in each spec; the financial kernel remains `Core::OperationalEvents`, `Core::Posting`, and `Core::Ledger`.
