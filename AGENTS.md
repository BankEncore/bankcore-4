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
```

- In Compose, Postgres is reachable at host **`db`** (`DATABASE_HOST=db`). In GitHub Actions, tests use **`localhost`** (see `.github/workflows/ci.yml`).
- **Do not commit** `config/master.key` or `.env`. Copy `.env.example` → `.env` locally.

## Apple Silicon + CI

- `Gemfile.lock` includes **`x86_64-linux`** so `bundle install` works on GitHub’s amd64 runners while you develop in **linux/arm64** containers locally.

## GitHub

- Remote target: **`BankEncore/bankcore-4`** (public). Create/push with `gh` only after you are authenticated (`gh auth login`); do not paste tokens into chat.
