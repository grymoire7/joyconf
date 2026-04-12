# Rename speechwave → speechwave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the application from `speechwave` to `speechwave` throughout the codebase — OTP app atom, module namespaces, directory structure, config keys, and database names.

**Architecture:** Pure mechanical rename. No functional changes. The OTP app atom changes from `:speechwave` to `:speechwave`, module prefix `Speechwave` → `Speechwave`, web module prefix `SpeechwaveWeb` → `SpeechwaveWeb`. Directories and files are renamed with `git mv` to preserve history, then content is updated with a bulk `sed` pass. Databases are dropped and recreated under the new names (dev data is lost).

**Tech Stack:** Elixir/Phoenix, Ecto/PostgreSQL, Git

---

## File Map

| File / Directory | Action | What changes |
|---|---|---|
| `lib/speechwave.ex` | Rename → `lib/speechwave.ex` | Module name |
| `lib/speechwave_web.ex` | Rename → `lib/speechwave_web.ex` | Module name, all internal references |
| `lib/speechwave/` | Rename dir → `lib/speechwave/` | All `Speechwave.*` module names |
| `lib/speechwave_web/` | Rename dir → `lib/speechwave_web/` | All `SpeechwaveWeb.*` module names |
| `test/speechwave/` | Rename dir → `test/speechwave/` | All module names and references |
| `test/speechwave_web/` | Rename dir → `test/speechwave_web/` | All module names and references |
| `test/support/*.ex` | Modify in place | Module names and references |
| `test/test_helper.exs` | Modify in place | OTP app atom if present |
| `mix.exs` | Modify in place | `app: :speechwave`, module name, esbuild/tailwind keys |
| `config/config.exs` | Modify in place | All `config :speechwave` keys, module refs, esbuild/tailwind keys |
| `config/dev.exs` | Modify in place | DB name, config keys, watcher keys, live-reload paths |
| `config/test.exs` | Modify in place | DB name, config keys |
| `config/prod.exs` | Modify in place | Config keys |
| `config/runtime.exs` | Modify in place | Config keys, release binary comment |
| `priv/repo/migrations/*.exs` | Modify in place | `Speechwave.Repo.Migrations.*` module names |
| `priv/repo/seeds.exs` | Modify in place | `Speechwave.Repo` comment reference |
| `docs/explainer.md` | Modify in place | `speechwave.fly.dev` URLs, directory listings |

---

## Task 1: Create Feature Branch

- [ ] **Step 1: Create and check out the rename branch**

  ```bash
  git checkout -b rename/speechwave-to-speechwave
  ```

  Expected output: `Switched to a new branch 'rename/speechwave-to-speechwave'`

---

## Task 2: Rename Files and Directories

Use `git mv` so Git tracks the renames and preserves blame history.

- [ ] **Step 1: Rename top-level lib files**

  ```bash
  cd /Users/tracy/projects/speechwave-live/speechwave
  git mv lib/speechwave.ex lib/speechwave.ex
  git mv lib/speechwave_web.ex lib/speechwave_web.ex
  ```

  Expected: no output (success is silent).

- [ ] **Step 2: Rename lib subdirectories**

  ```bash
  git mv lib/speechwave lib/speechwave
  git mv lib/speechwave_web lib/speechwave_web
  ```

  Expected: no output.

- [ ] **Step 3: Rename test subdirectories**

  ```bash
  git mv test/speechwave test/speechwave
  git mv test/speechwave_web test/speechwave_web
  ```

  Expected: no output.

- [ ] **Step 4: Verify the renames are staged**

  ```bash
  git status --short | grep -E "^R"
  ```

  Expected: 6 lines each starting with `R ` showing the old → new path pairs.

---

## Task 3: Bulk Content Update

A single `sed` pass replaces all `Speechwave`/`speechwave` occurrences in every source file. The rule `s/Speechwave/Speechwave/g` handles `SpeechwaveWeb` → `SpeechwaveWeb` as a subset match. The rule `s/speechwave/speechwave/g` handles `speechwave_web`, `speechwave_dev`, `speechwave_test`, and `_speechwave_key`.

- [ ] **Step 1: Run the bulk substitution**

  ```bash
  cd /Users/tracy/projects/speechwave-live/speechwave
  LC_ALL=C find . -type f \( \
    -name "*.ex" -o -name "*.exs" -o -name "*.md" \
  \) \
  | grep -v "\\./_build\|\\./deps\|\\./\\.git\|\\./node_modules\|\\./extension/node_modules" \
  | xargs sed -i '' \
    -e 's/Speechwave/Speechwave/g' \
    -e 's/speechwave/speechwave/g'
  ```

  Expected: no output (success is silent for `sed`).

- [ ] **Step 2: Spot-check that no `speechwave` references remain in source files**

  ```bash
  grep -r "speechwave\|Speechwave" \
    --include="*.ex" --include="*.exs" --include="*.md" \
    --exclude-dir=_build --exclude-dir=deps --exclude-dir=.git \
    --exclude-dir=node_modules \
    .
  ```

  Expected: no output. If any lines appear, fix them manually before proceeding.

---

## Task 4: Recreate Databases

The config now references `speechwave_dev` and `speechwave_test`. The old databases (`speechwave_dev`, `speechwave_test`) still exist in Postgres but are no longer referenced. Drop the old ones, then set up fresh under the new names.

> **Note:** Local dev data (talks, sessions, reactions) will be lost. This is expected for a rename.

- [ ] **Step 1: Drop the old databases**

  ```bash
  psql -U postgres -c "DROP DATABASE IF EXISTS speechwave_dev;"
  psql -U postgres -c "DROP DATABASE IF EXISTS speechwave_test;"
  ```

  Expected:
  ```
  DROP DATABASE
  DROP DATABASE
  ```

- [ ] **Step 2: Create and migrate the new dev database**

  ```bash
  mix ecto.setup
  ```

  Expected: Creates `speechwave_dev`, runs all migrations, runs seeds without errors.

- [ ] **Step 3: Verify the test database is ready**

  The `mix precommit` in Task 5 runs `mix test` which calls `ecto.create --quiet` and `ecto.migrate --quiet` in the test environment automatically (see the `test` alias in `mix.exs`). No manual step needed here.

---

## Task 5: Run Precommit and Fix Issues

- [ ] **Step 1: Run the full precommit check**

  ```bash
  mix precommit
  ```

  Expected: compiles without warnings, all tests pass, no unused deps, formatting clean.

  If compilation fails, read the error carefully — it will name the module and line. The most common cause is a missed substitution. Fix it, re-run `mix precommit`.

  If tests fail, check whether the failure is a substitution miss (module name not found) or a genuine test regression (should not happen for a pure rename).

---

## Task 6: Commit

- [ ] **Step 1: Stage all changes**

  ```bash
  git add -A
  ```

- [ ] **Step 2: Verify the staged diff looks right**

  ```bash
  git diff --cached --stat
  ```

  Expected: many files renamed and modified. No unexpected deletions.

- [ ] **Step 3: Commit**

  ```bash
  git commit -m "$(cat <<'EOF'
  refactor: rename speechwave → speechwave throughout codebase

  Renames OTP app atom (:speechwave → :speechwave), all Elixir module
  prefixes (Speechwave → Speechwave, SpeechwaveWeb → SpeechwaveWeb),
  directory structure (lib/speechwave* → lib/speechwave*,
  test/speechwave* → test/speechwave*), config keys, database names
  (speechwave_dev/test → speechwave_dev/test), and cookie session key.
  EOF
  )"
  ```

- [ ] **Step 4: Push the branch**

  ```bash
  git push -u origin rename/speechwave-to-speechwave
  ```
