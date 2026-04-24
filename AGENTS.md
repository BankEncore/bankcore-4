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

**Cash variance threshold:** `TELLER_VARIANCE_THRESHOLD_MINOR_UNITS` (integer, default **0**). If `abs(actual - expected)` is **greater** than this value when closing a session, status becomes **`pending_supervisor`** until a supervisor calls **`approve_variance`**. When the threshold is **0**, any non-zero variance requires supervisor approval.

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
