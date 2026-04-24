# bankcore-4 — agent and contributor notes

## Stack

- **Rails** 8.1 (app module `BankCore4`), **PostgreSQL**, **Importmap**, **Tailwind** (`tailwindcss-rails`).
- **Docker Compose** is the default dev runtime: `web` (Ruby) + `db` (Postgres 16). `web` runs **Foreman** (`Procfile.dev`: Rails + Tailwind) via `bundle exec foreman`.
- **Dev Container**: open the repo in a container using `.devcontainer/devcontainer.json` (Compose-backed).

## Commands (prefer Docker)

```bash
docker compose build
docker compose up
docker compose run --rm web bin/rails db:prepare
docker compose run --rm web bin/rails test
docker compose run --rm web bin/rubocop -A
```

- In Compose, Postgres is reachable at host **`db`** (`DATABASE_HOST=db`). In GitHub Actions, tests use **`localhost`** (see `.github/workflows/ci.yml`).
- **Do not commit** `config/master.key` or `.env`. Copy `.env.example` → `.env` locally.

## Apple Silicon + CI

- `Gemfile.lock` includes **`x86_64-linux`** so `bundle install` works on GitHub’s amd64 runners while you develop in **linux/arm64** containers locally.

## GitHub

- Remote target: **`BankEncore/bankcore-4`** (public). Create/push with `gh` only after you are authenticated (`gh auth login`); do not paste tokens into chat.

## Teller JSON workspace (local / curl)

After `bin/rails db:seed` in **development**, sample **`operators`** rows exist (teller and supervisor). Send **`X-Operator-Id: <id>`** on every `POST /teller/…` and **`GET /teller/reports/…`** request (`Content-Type: application/json` on writes). Use a **supervisor** operator id for **`POST /teller/reversals`**, **`POST /teller/business_date/close`** (after EOD readiness), **`override.approved`** on **`POST /teller/overrides`**, and **`POST /teller/teller_sessions/approve_variance`**. See [docs/adr/0015-teller-workspace-authentication.md](docs/adr/0015-teller-workspace-authentication.md).

**Trial balance / EOD readiness:** `GET /teller/reports/trial_balance` and `GET /teller/reports/eod_readiness` with optional query **`business_date`** (ISO **YYYY-MM-DD**); omit to use the current core business date. Response includes **`current_business_on`** and **`posting_day_closed`** (true when the requested date is before the open singleton day). See [docs/adr/0016-trial-balance-and-eod-readiness.md](docs/adr/0016-trial-balance-and-eod-readiness.md) and [docs/adr/0018-business-date-close-and-posting-invariant.md](docs/adr/0018-business-date-close-and-posting-invariant.md).

**Business date close:** **`POST /teller/business_date/close`** (supervisor) advances **`current_business_on`** only when ADR-0016 readiness is satisfied for the day being closed. Optional JSON **`{ "business_date": "YYYY-MM-DD" }`** must match that open day if sent. Routine financial and hold APIs reject an explicit **`business_date`** that is not the current open day.

**Event type catalog (discovery):** **`GET /teller/event_types`** — JSON **`{ "event_types": [ … ] }`**; each object includes **`event_type`**, **`category`**, **`posts_to_gl`**, **`record_command`**, **`reversible_via_posting_reversal`**, **`compensating_event_type`**, **`description`**. Same **`X-Operator-Id`** header as other teller JSON reads. See [docs/adr/0019-event-catalog-and-fee-events.md](docs/adr/0019-event-catalog-and-fee-events.md).

**Holds:** **`POST /teller/holds`** (JSON `hold` object) creates an **`active`** hold and a posted **`hold.placed`** event. Optional **`placed_for_operational_event_id`** (integer) links the hold to a **posted** **`deposit.accepted`** on the same **`deposit_account_id`**; the sum of **active** holds on that deposit cannot exceed the deposit amount (ADR-0013 §3). **`POST /teller/holds/release`** releases a hold (**`hold_release`** payload). Reversing a deposit via **`POST /teller/reversals`** is rejected while any **active** hold still references that deposit id.

**Recording fees:** **`POST /teller/operational_events`** accepts **`event_type: "fee.assessed"`** or **`"fee.waived"`** with the usual **`amount_minor_units`**, **`currency`**, **`source_account_id`**, **`channel`**, **`idempotency_key`**. **`fee.waived`** requires **`reference_id`** (string) equal to the **numeric id** of a **posted** **`fee.assessed`** for the same account and amount. **`fee.assessed`** is **not** reversed via **`posting.reversal`**; use **`fee.waived`**.

**Fee engine:** monthly maintenance fees are product-configured in `deposit_product_fee_rules` and assessed by `Accounts::Commands::AssessMonthlyMaintenanceFees` as **system-channel** `fee.assessed` events. The command uses deterministic idempotency per business date/rule/account, immediately posts created fees, and marks engine origin in `reference_id` as `monthly_maintenance:<rule_id>:<business_date>` (ADR-0022).

**Overdraft / NSF:** teller `withdrawal.posted` and `transfer.completed` creates route through `Accounts::Commands::AuthorizeDebit`. If available balance is insufficient and the product has an active **`deny_nsf`** policy, the attempted transaction is denied (no withdrawal/transfer event), a posted no-GL **`overdraft.nsf_denied`** event is recorded, and a forced **system-channel** NSF `fee.assessed` is posted with `reference_id: "nsf_denial:<denial_event_id>"` (ADR-0023).

**Interest:** **`interest.accrued`** and **`interest.posted`** are **system-channel only** financial events (not teller cash). `interest.posted` requires **`reference_id`** equal to a **posted** **`interest.accrued`** for the same account, amount, and currency. Amounts remain **minor units** at the operational-event and journal layers; sub-minor/microcent accrual belongs to a future engine accumulator (ADR-0021).

**Operational events (observability):** **`GET /teller/operational_events`** — query params: optional **`business_date`** (single day) **or** **`business_date_from`** + **`business_date_to`** (inclusive, max 31 days); optional **`source_account_id`**, **`destination_account_id`**, **`status`**, **`event_type`**, **`channel`**, **`actor_id`**, **`deposit_product_id`**, **`product_code`**; pagination **`limit`** (default 50, max 200) and **`after_id`**. No date after **`current_business_on`**. Response includes **`current_business_on`**, **`posting_day_closed`**, **`business_date_from`**, **`business_date_to`**, **`next_after_id`**, **`has_more`**, and **`events`** (each with **`source_account`** / **`destination_account`** product summary when linked, plus **`posting_batch_ids`** and **`journal_entry_ids`**). See [docs/adr/0017-deposit-products-fk-narrow-scope.md](docs/adr/0017-deposit-products-fk-narrow-scope.md) §2.5.

**Cash variance threshold:** `TELLER_VARIANCE_THRESHOLD_MINOR_UNITS` (integer, default **0**). If `abs(actual - expected)` is **greater** than this value when closing a session, status becomes **`pending_supervisor`** until a supervisor calls **`approve_variance`**. When the threshold is **0**, any non-zero variance requires supervisor approval.

**GL posting for drawer variance (optional):** `TELLER_POST_DRAWER_VARIANCE_TO_GL` (default **false**). When enabled, **`CloseSession`** / **`ApproveSessionVariance`** create and post **`teller.drawer.variance.posted`** (`system` channel, signed `amount_minor_units`, GL **1110** / **5190**) for non-zero variance. See [docs/adr/0020-teller-drawer-variance-gl-posting.md](docs/adr/0020-teller-drawer-variance-gl-posting.md).

**Open session for teller cash:** `TELLER_REQUIRE_OPEN_SESSION_FOR_CASH` (default **true**). When enabled, **`channel: teller`** **`deposit.accepted`** and **`withdrawal.posted`** require **`teller_session_id`** referencing an **open** session (`transfer.completed` exempt). Set to **`false`**, **`0`**, or **`no`** to disable.

**Deposit products:** `POST /teller/deposit_accounts` accepts optional **`deposit_product_id`** and **`product_code`** on `deposit_account` (defaults to seeded slice-1 product). Optional **`joint_party_record_id`** opens a two-party joint account (second `deposit_account_parties` row, `joint_owner`). Response includes **`deposit_product_id`**, **`product_code`**, and **`product_name`**. See [docs/adr/0017-deposit-products-fk-narrow-scope.md](docs/adr/0017-deposit-products-fk-narrow-scope.md) and [docs/adr/0011-accounts-deposit-vertical-slice-mvp.md](docs/adr/0011-accounts-deposit-vertical-slice-mvp.md) §2.3.

## Documentation pointers

- **[docs/concepts/01-mvp-vs-core.md](docs/concepts/01-mvp-vs-core.md)** — MVP vs full-system boundaries (“branch safely”).
- **[docs/architecture/bankcore-module-catalog.md](docs/architecture/bankcore-module-catalog.md)** — domain modules and ownership.
- **[docs/roadmap.md](docs/roadmap.md)** — draft engineering sequence (does not redefine MVP scope).

## Cursor project rules (BankCORE)

- **`.cursor/rules/bankcore-planning.mdc`** — always on: MVP gating, modular monolith, kernel vs operational events, doc sources under `docs/`.
- **`.cursor/rules/bankcore-docs-and-adrs.mdc`** — when editing `docs/**`: domain ↔ module mapping, ADR triggers, writing style.
- **`.cursor/rules/bankcore-implementation.mdc`** — when editing Ruby / `Gemfile` / migrations: controllers vs domains, posting path, test invariants.

Existing rules: `core-workflow.mdc`, `rails-ruby.mdc`, `docker-ci.mdc`.

## Cursor project skill (module catalog)

- **`.cursor/skills/bankcore-module-ruby/`** — Agent skill to align Ruby/Rails work with [`docs/architecture/bankcore-module-catalog.md`](docs/architecture/bankcore-module-catalog.md); see `SKILL.md` and `reference.md` inside that folder.
