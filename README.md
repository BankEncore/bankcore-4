# bankcore-4

Rails 8.1 app (**BankCore4**): PostgreSQL, Importmap, Tailwind, Docker Compose, Dev Container, and GitHub Actions CI.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Apple Silicon is supported; containers run as **linux/arm64** by default).
- Optional: [GitHub CLI](https://cli.github.com/) (`gh`) for creating the **`BankEncore/bankcore-4`** remote.

## Quick start

```bash
cp .env.example .env   # optional; Compose already sets env for `web`
docker compose build
docker compose up
```

Open [http://localhost:3000](http://localhost:3000). The `web` service runs **`bundle exec foreman start -f Procfile.dev`** (Rails on `0.0.0.0` + Tailwind watcher). On the host you can use **`bin/dev`** after `bundle install` if `foreman` is on your `PATH`.

Database prep (if needed):

```bash
docker compose run --rm web bin/rails db:prepare
```

## Tests

```bash
docker compose run --rm web bin/rails test
```

**Parallel tests (optional later):** the default setup uses a single `bank_core4_test` database on the Compose `db` service. If you add process-level parallel runners (for example `parallel_tests`), use per-worker database names (for example `TEST_ENV_NUMBER`) and document `db:create` / `parallel:create` for all worker DBs.

## Credentials

`config/master.key` is **gitignored**. For local Docker you can mount or copy the key; for production deploys use `RAILS_MASTER_KEY` in your host or orchestrator. Tests are configured with `config.require_master_key = false` so CI can run without a GitHub secret until you rely on encrypted credentials in the test suite.

## Dev Container

Use **“Dev Containers: Reopen in Container”** in VS Code or Cursor. See [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json).

## More

See [AGENTS.md](AGENTS.md) for stack summary and agent-oriented notes.
