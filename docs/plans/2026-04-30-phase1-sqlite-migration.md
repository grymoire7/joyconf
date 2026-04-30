# Phase 1: SQLite Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PostgreSQL with SQLite backed by Litestream replication to Tigris, eliminating the out-of-memory crashes on fly.io's free tier.

**Architecture:** `ecto_sqlite3` replaces `postgrex`. The database file lives at `/data/speechwave.db` on a fly.io persistent volume. A wrapper startup script handles backup restore, runs migrations, then starts the app under `litestream replicate` so every WAL write is streamed to Tigris object storage. Development and test use local file-based SQLite databases. One Postgres-specific fragment (`EXTRACT(EPOCH FROM ...)`) is rewritten to the SQLite equivalent (`strftime('%s', ...)`).

**Tech Stack:** Elixir, Phoenix, Ecto, `ecto_sqlite3`, Litestream, fly.io Volumes, Tigris (S3-compatible)

---

## File Map

### Modified
| File | Change |
|---|---|
| `mix.exs` | Replace `postgrex` with `ecto_sqlite3` |
| `config/dev.exs` | Replace Postgres config with SQLite file path |
| `config/test.exs` | Replace Postgres config with SQLite file path |
| `config/runtime.exs` | Replace Postgres URL config with SQLite path config |
| `lib/speechwave/talks.ex` | Rewrite `EXTRACT(EPOCH …)` fragment to `strftime('%s', …)` |
| `Dockerfile` | Install Litestream binary in runner stage; change `CMD` |
| `fly.toml` | Remove `release_command`; add `[mounts]` section |

### Created
| File | Purpose |
|---|---|
| `rel/overlays/bin/start` | Startup wrapper: restore → migrate → replicate |
| `rel/overlays/etc/litestream.yml` | Litestream replication config |

### Deleted
None.

---

## Task 1: Replace Postgres with SQLite in deps and config

**Files:**
- Modify: `mix.exs`
- Modify: `config/dev.exs`
- Modify: `config/test.exs`
- Modify: `config/runtime.exs`

- [ ] **Step 1: Write a test that will confirm the SQLite fragment works**

In `test/speechwave/talks_test.exs`, verify the `count_full_sessions_this_month/1` test exists. Run it now so you know it passes with the current Postgres fragment — you will use this as confirmation that it still passes after the migration.

```bash
mix test test/speechwave/talks_test.exs --grep "count_full_sessions"
```

Expected: passing tests. Note the count — you'll re-run this in Task 2 to confirm nothing broke.

- [ ] **Step 2: Update `mix.exs` dependencies**

In `mix.exs`, in the `deps/0` function, replace:

```elixir
{:postgrex, ">= 0.0.0"},
```

with:

```elixir
{:ecto_sqlite3, "~> 0.18"},
```

- [ ] **Step 3: Fetch new deps**

```bash
mix deps.get
```

Expected: `ecto_sqlite3` and its transitive deps (e.g., `exqlite`) downloaded.

- [ ] **Step 4: Update `config/dev.exs`**

Replace the entire `config :speechwave, Speechwave.Repo` block with:

```elixir
config :speechwave, Speechwave.Repo,
  database: Path.expand("../speechwave_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true
```

Remove or comment out `username`, `password`, `hostname` — SQLite does not use them.

- [ ] **Step 5: Update `config/test.exs`**

Replace the `config :speechwave, Speechwave.Repo` block with:

```elixir
config :speechwave, Speechwave.Repo,
  database: Path.expand("../priv/repo/test#{System.get_env("MIX_TEST_PARTITION", "")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

- [ ] **Step 6: Update `config/runtime.exs`**

In the `if config_env() == :prod do` block, replace the `config :speechwave, Speechwave.Repo` block (which currently reads `DATABASE_URL`) with:

```elixir
database_path =
  System.get_env("DATABASE_PATH") ||
    raise """
    environment variable DATABASE_PATH is missing.
    Set it to the SQLite file path, e.g. /data/speechwave.db
    """

config :speechwave, Speechwave.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))
```

Remove the lines that reference `DATABASE_URL`, `maybe_ipv6`, and `socket_options` — those are Postgres-specific.

- [ ] **Step 7: Update the Repo adapter**

Open `lib/speechwave/repo.ex`. Change the adapter line:

```elixir
# Before:
use Ecto.Repo,
  otp_app: :speechwave,
  adapter: Ecto.Adapters.Postgres

# After:
use Ecto.Repo,
  otp_app: :speechwave,
  adapter: Ecto.Adapters.SQLite3
```

- [ ] **Step 8: Drop the test database alias for ecto.create**

With SQLite, `ecto.create` is not needed — the file is created automatically on first connect. The `test` alias currently runs `ecto.create --quiet`. Update `mix.exs`:

```elixir
test: ["ecto.migrate --quiet", "test"],
```

- [ ] **Step 9: Add SQLite dev/test db files to .gitignore**

Open `.gitignore` and add:

```
# SQLite databases
*.db
*.db-shm
*.db-wal
```

- [ ] **Step 10: Reset and migrate the dev database**

```bash
mix ecto.drop --quiet 2>/dev/null; mix ecto.migrate
```

Expected: Migrations run successfully. A `speechwave_dev.db` file is created in the project root.

- [ ] **Step 11: Compile to surface any remaining adapter errors**

```bash
mix compile --warnings-as-errors
```

Expected: Clean compile. If you see `postgrex` references in generated files or lockfile, run `mix deps.unlock postgrex && mix deps.get`.

- [ ] **Step 12: Commit**

```bash
git add mix.exs mix.lock config/dev.exs config/test.exs config/runtime.exs lib/speechwave/repo.ex .gitignore
git commit -m "feat: replace PostgreSQL with SQLite via ecto_sqlite3"
```

---

## Task 2: Fix the Postgres-specific query

**Files:**
- Modify: `lib/speechwave/talks.ex`

- [ ] **Step 1: Run the failing test to confirm it breaks with SQLite**

```bash
mix test test/speechwave/talks_test.exs --grep "count_full_sessions"
```

Expected: Test fails with an error like `no such function: EXTRACT` or similar SQLite complaint. This confirms the fragment must be rewritten.

- [ ] **Step 2: Rewrite the fragment in `count_full_sessions_this_month/1`**

In `lib/speechwave/talks.ex`, locate the `where:` clause inside `count_full_sessions_this_month/1`:

```elixir
# Before:
where: fragment("EXTRACT(EPOCH FROM (? - ?)) > 600", s.ended_at, s.started_at)

# After:
where: fragment("(strftime('%s', ?) - strftime('%s', ?)) > 600", s.ended_at, s.started_at)
```

`strftime('%s', datetime_string)` returns the Unix epoch for a datetime stored in SQLite's "YYYY-MM-DD HH:MM:SS" text format, which is what `ecto_sqlite3` uses for `:utc_datetime` fields.

- [ ] **Step 3: Run the full test suite**

```bash
mix test
```

Expected: All pass. The `count_full_sessions` tests should now be green.

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave/talks.ex
git commit -m "fix: rewrite EXTRACT(EPOCH) fragment for SQLite compatibility"
```

---

## Task 3: Set up Litestream for production replication

**Files:**
- Create: `rel/overlays/bin/start`
- Create: `rel/overlays/etc/litestream.yml`
- Modify: `Dockerfile`
- Modify: `fly.toml`

- [ ] **Step 1: Create the `rel/overlays/` directory structure**

```bash
mkdir -p rel/overlays/bin rel/overlays/etc
```

- [ ] **Step 2: Create `rel/overlays/etc/litestream.yml`**

```yaml
dbs:
  - path: ${DATABASE_PATH}
    replicas:
      - type: s3
        bucket: ${LITESTREAM_BUCKET}
        path: speechwave
        region: auto
        endpoint: ${LITESTREAM_URL}
        access-key-id: ${LITESTREAM_ACCESS_KEY_ID}
        secret-access-key: ${LITESTREAM_SECRET_ACCESS_KEY}
```

Environment variables are expanded at runtime by Litestream. All four (`LITESTREAM_BUCKET`, `LITESTREAM_URL`, `LITESTREAM_ACCESS_KEY_ID`, `LITESTREAM_SECRET_ACCESS_KEY`) must be set as fly.io secrets before deploying.

- [ ] **Step 3: Create `rel/overlays/bin/start`**

```bash
#!/bin/bash
set -eu

DATABASE_PATH="${DATABASE_PATH:-/data/speechwave.db}"
export DATABASE_PATH

# Restore from Tigris backup if the database doesn't exist (e.g. after a volume loss)
if [ -n "${LITESTREAM_URL:-}" ] && [ ! -f "$DATABASE_PATH" ]; then
  echo "[start] No database found — attempting restore from replica..."
  litestream restore -if-replica-exists -config /app/etc/litestream.yml "$DATABASE_PATH" \
    && echo "[start] Restore complete." \
    || echo "[start] No replica found or restore failed — starting fresh."
fi

# Run Ecto migrations
echo "[start] Running migrations..."
/app/bin/migrate

# Start Phoenix under Litestream replication, or directly if Litestream is not configured
if [ -n "${LITESTREAM_URL:-}" ]; then
  echo "[start] Starting server under Litestream replication..."
  exec litestream replicate -exec "/app/bin/server" -config /app/etc/litestream.yml
else
  echo "[start] LITESTREAM_URL not set — starting server without replication."
  exec /app/bin/server
fi
```

- [ ] **Step 4: Make the start script executable**

```bash
chmod +x rel/overlays/bin/start
```

- [ ] **Step 5: Update `Dockerfile` runner stage**

In the runner stage (after `FROM ${RUNNER_IMAGE}`), add a step to install Litestream. Place it after the existing `apt-get` block:

```dockerfile
# Install Litestream for SQLite WAL replication
ARG LITESTREAM_VERSION=v0.3.13
RUN apt-get update -y && \
    apt-get install -y curl && \
    curl -sL "https://github.com/benbjohnson/litestream/releases/download/${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin litestream && \
    apt-get remove -y curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*
```

Also change the final `CMD` line at the bottom of the Dockerfile:

```dockerfile
# Before:
CMD ["/app/bin/server"]

# After:
CMD ["/app/bin/start"]
```

- [ ] **Step 6: Update `fly.toml`**

Remove the `[deploy]` section (migrations are now handled in `start`):

```toml
# Remove these lines:
[deploy]
  release_command = '/app/bin/migrate'
```

Add a `[mounts]` section to persist the SQLite database across deploys:

```toml
[[mounts]]
  source = "speechwave_data"
  destination = "/data"
```

The full updated fly.toml should look like:

```toml
app = 'speechwave'
primary_region = 'iad'
console_command = '/app/bin/speechwave remote'

[build]

[env]
  PHX_HOST = 'speechwave.fly.dev'
  PORT = '8080'
  DATABASE_PATH = '/data/speechwave.db'

[[mounts]]
  source = 'speechwave_data'
  destination = '/data'

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 0
  processes = ['app']

  [http_service.concurrency]
    type = 'connections'
    hard_limit = 1000
    soft_limit = 1000

[[vm]]
  memory = '256mb'
  cpu_kind = 'shared'
  cpus = 1
```

Note the memory is changed to `256mb` — SQLite runs in-process so the app fits comfortably within the free tier limit.

- [ ] **Step 7: Create the fly.io volume (run once)**

This step runs on your machine. If you have not already created the volume:

```bash
fly volumes create speechwave_data --region iad --size 1
```

Expected: Volume created. Verify with `fly volumes list`.

- [ ] **Step 8: Set Litestream secrets in fly.io**

Obtain Tigris credentials from the fly.io dashboard (Storage → your bucket → Access Keys).

```bash
fly secrets set \
  LITESTREAM_URL="https://fly.storage.tigris.dev" \
  LITESTREAM_BUCKET="your-tigris-bucket-name" \
  LITESTREAM_ACCESS_KEY_ID="tid_xxxx" \
  LITESTREAM_SECRET_ACCESS_KEY="your_secret"
```

Also set the other required secrets if not already present:

```bash
fly secrets set \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  PHX_HOST="speechwave.fly.dev"
```

- [ ] **Step 9: Commit**

```bash
git add rel/overlays/bin/start rel/overlays/etc/litestream.yml Dockerfile fly.toml
git commit -m "feat: configure Litestream replication and fly.io volume for SQLite"
```

---

## Task 4: Verify production build locally and run precommit

- [ ] **Step 1: Build the Docker image locally**

```bash
docker build -t speechwave-local .
```

Expected: Build succeeds. Look for "Litestream" in the output confirming it was installed.

- [ ] **Step 2: Run the full test suite**

```bash
mix test
```

Expected: All pass.

- [ ] **Step 3: Run precommit**

```bash
mix precommit
```

Expected: No errors. Fix any formatting issues and commit:

```bash
git add -A
git commit -m "chore: fix precommit issues after SQLite migration"
```

Only create this commit if there are actual changes; skip if clean.

- [ ] **Step 4: Deploy to fly.io**

```bash
fly deploy
```

Watch the logs. Expected sequence:
1. `[start] No database found — attempting restore from replica...` (first deploy only) or `[start] Running migrations...`
2. Migrations apply
3. `[start] Starting server under Litestream replication...`
4. App starts and Litestream begins replication

- [ ] **Step 5: Verify Litestream is replicating**

```bash
fly ssh console -C "litestream snapshots -config /app/etc/litestream.yml /data/speechwave.db"
```

Expected: Shows at least one snapshot entry in Tigris, confirming replication is active.
