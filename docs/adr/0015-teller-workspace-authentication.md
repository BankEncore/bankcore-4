# ADR-0015: Teller workspace authentication (operators)

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [module catalog](../architecture/bankcore-module-catalog.md) §10, [ADR-0014](0014-teller-sessions-and-control-events.md), [ADR-0002](0002-operational-event-model.md)

---

## 1. Decision

- **`operators`** is the canonical **system-wide** table for “who acted?” (teller workspace today; other channels later). It is owned by **`Workspace`** (`Workspace::Models::Operator`). **`Teller`** owns **sessions and drawer state** and may reference operators; it does not own the operator row.
- **Teller JSON** requests require header **`X-Operator-Id`** with a **numeric** primary key of an **active** operator row. Missing/invalid/unknown/inactive → **401** with JSON `{ "error": "unauthorized", … }`.
- **Role** (`teller` \| `supervisor`) is read **only from the database** on that row. Clients must **not** send a trusted role header; spoofing is rejected by design.
- **Supervisor-only HTTP actions** (Phase 1): creating a **`posting.reversal`** operational event via `POST /teller/reversals`, **`override.approved`** via `POST /teller/overrides`, and **`POST /teller/teller_sessions/approve_variance`** (material cash variance on session close per [ADR-0014](0014-teller-sessions-and-control-events.md)). Other teller actions allow any active operator with either role (supervisors may perform teller duties).
- **`operational_events.actor_id`** references **`operators.id`** (FK). Controllers pass **`current_operator.id`** into **`RecordEvent`**, **`RecordReversal`**, and **`RecordControlEvent`** where applicable.
- **Production** trust boundary: mutual TLS, network policy, and/or future OAuth/JWT remain out of scope for this ADR; the MVP contract is explicit headers plus DB-backed identity.

---

## 2. Consequences

- Development seeds create sample teller and supervisor operators (`db/seeds.rb` when `Rails.env.development?`).
- Integration tests must send **`X-Operator-Id`** on all teller workspace requests.
