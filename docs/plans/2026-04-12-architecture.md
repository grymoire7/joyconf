# Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the production architecture for Speechwave: GitHub org + two-repo structure, BSL 1.1 licensing on the Phoenix app, MIT on the extension, and a `Speechwave.Plans` module that defines and enforces free/pro/org tier limits.

**Architecture:** Single public monolith under a `speechwave-live` GitHub org. Tier limits enforced in application logic via `Speechwave.Plans` — a pattern-matched constants module — not environment variables. The Chrome extension is extracted to its own repo with its own release lifecycle.

**Tech Stack:** Elixir/Phoenix, ExUnit, Git, GitHub

---

## File Map

| File | Action | Responsibility |
| --- | --- | --- |
| `LICENSE` | Create | BSL 1.1 license for the Phoenix app |
| `LICENSE_FAQ.md` | Create | Plain-language explanation of BSL terms |
| `lib/speechwave/plans.ex` | Create | Tier limit constants and `check/3` enforcement function |
| `test/speechwave/plans_test.exs` | Create | Unit tests for `Speechwave.Plans` |

Extension repo (separate repo, manual setup):

| File | Action | Responsibility |
| --- | --- | --- |
| `LICENSE` | Create | MIT license for the Chrome extension |

---

## Task 1: Create the `speechwave-live` GitHub Organization

Manual steps — no code.

- [x] **Step 1: Create the org**

  Go to https://github.com/organizations/plan and create a new organization named `speechwave-live`. Select the free plan.

- [x] **Step 2: Transfer the speechwave repo**

  On GitHub: go to the `speechwave` repo → Settings → Danger Zone → Transfer repository. Transfer to `speechwave-live`. The repo will be accessible at `github.com/speechwave-live/speechwave` (it will be renamed to `speechwave` in the rename phase).

- [x] **Step 3: Update the local remote**

  ```bash
  git remote set-url origin git@github.com:speechwave-live/speechwave.git
  git remote -v
  ```

  Expected output includes `speechwave-live/speechwave`.

---

## Task 2: Extract the Chrome Extension to its Own Repo

- [x] **Step 1: Create the new extension repo on GitHub**

  On GitHub under `speechwave-live`, create a new empty public repo named `chrome-extension`. Do not initialize with a README.

- [x] **Step 2: Copy extension files to a temp directory**

  ```bash
  cp -r extension /tmp/chrome-extension
  ```

- [x] **Step 3: Initialize and push the extension repo**

  ```bash
  cd /tmp/speechwave-extension
  git init
  git add .
  git commit -m "chore: initial commit — extracted from speechwave monorepo"
  git remote add origin git@github.com:speechwave-live/extension.git
  git branch -M main
  git push -u origin main
  ```

- [x] **Step 4: Add MIT license to the extension repo**

  Create `/tmp/speechwave-extension/LICENSE` with the standard MIT text (available at https://opensource.org/license/mit), substituting "Tracy Atteberry" as the copyright holder and "2026" as the year. Commit and push:

  ```bash
  git add LICENSE
  git commit -m "chore: add MIT license"
  git push
  ```

- [x] **Step 5: Clone the extension repo to a permanent location**

  The `/tmp` directory is ephemeral. Clone the pushed repo to wherever you keep projects:

  ```bash
  git clone git@github.com:speechwave-live/extension.git ~/projects/speechwave-extension
  ```

- [x] **Step 6: Remove the extension directory from the main repo**

  Back in the speechwave project directory:

  ```bash
  cd /Users/tracy/projects/speechwave
  git rm -r extension/
  git commit -m "chore: remove extension — moved to speechwave-live/extension"
  git push
  ```

---

## Task 3: Add BSL 1.1 License to the Phoenix App

- [x] **Step 1: Create the LICENSE file**

  Create `LICENSE` in the project root. Use the BSL 1.1 template from https://mariadb.com/bsl11/ with these fields:

  - Licensor: Tracy Atteberry
  - Licensed Work: Speechwave
  - Additional Use Grant: You may use the Licensed Work for personal, non-commercial, and development purposes, including self-hosting for non-commercial use.
  - Change Date: Four years from the release date of each version
  - Change License: Apache License 2.0

- [x] **Step 2: Create LICENSE_FAQ.md**

  Create `LICENSE_FAQ.md` in the project root:

  ```markdown
  # License FAQ

  Speechwave is licensed under the [Business Source License 1.1](LICENSE) (BSL 1.1).
  Here is what that means in plain language.

  ## What can I do for free?

  - Read, study, and fork the code
  - Run Speechwave locally for development or personal experimentation
  - Self-host Speechwave for non-commercial use (e.g. for your own talks, for free)

  ## What requires a commercial license?

  Running Speechwave as a commercial service — for example, offering it as a
  hosted product to paying customers or charging attendees — requires a separate
  license. Contact tracy@speechwave.live to discuss.

  ## What about the hosted version at speechwave.live?

  That is the official hosted service. The free tier is available to anyone.
  Paid tiers (Pro, Organization) are coming soon.

  ## When does the license expire?

  Each released version of Speechwave automatically becomes available under the
  Apache License 2.0 four years after its release date. At that point you may
  use it under the terms of Apache 2.0.

  ## What about the Chrome extension?

  The Chrome extension lives in a separate repository
  (github.com/speechwave-live/extension) and is licensed under MIT.
  ```

- [x] **Step 3: Commit**

  ```bash
  git add LICENSE LICENSE_FAQ.md
  git commit -m "chore: add BSL 1.1 license and FAQ"
  git push
  ```

---

## Task 4: Create the `Speechwave.Plans` Module

- [x] **Step 1: Write the failing test**

  Create `test/speechwave/plans_test.exs`:

  ```elixir
  defmodule Speechwave.PlansTest do
    use ExUnit.Case, async: true

    alias Speechwave.Plans

    describe "limit/2 — free plan" do
      test "max_participants is 50" do
        assert Plans.limit(:max_participants, :free) == 50
      end

      test "full_sessions_per_month is 10" do
        assert Plans.limit(:full_sessions_per_month, :free) == 10
      end
    end

    describe "limit/2 — pro plan" do
      test "max_participants is unlimited" do
        assert Plans.limit(:max_participants, :pro) == :unlimited
      end

      test "full_sessions_per_month is unlimited" do
        assert Plans.limit(:full_sessions_per_month, :pro) == :unlimited
      end
    end

    describe "limit/2 — org plan" do
      test "inherits pro max_participants" do
        assert Plans.limit(:max_participants, :org) == Plans.limit(:max_participants, :pro)
      end

      test "inherits pro full_sessions_per_month" do
        assert Plans.limit(:full_sessions_per_month, :org) ==
                 Plans.limit(:full_sessions_per_month, :pro)
      end
    end

    describe "check/3" do
      test "returns :ok when count is below the free limit" do
        assert Plans.check(:max_participants, :free, 49) == :ok
      end

      test "returns {:error, :limit_reached} when count equals the free limit" do
        assert Plans.check(:max_participants, :free, 50) == {:error, :limit_reached}
      end

      test "returns {:error, :limit_reached} when count exceeds the free limit" do
        assert Plans.check(:max_participants, :free, 51) == {:error, :limit_reached}
      end

      test "returns :ok for pro plan regardless of count" do
        assert Plans.check(:max_participants, :pro, 1_000_000) == :ok
      end

      test "returns :ok for org plan regardless of count" do
        assert Plans.check(:max_participants, :org, 1_000_000) == :ok
      end

      test "returns :ok for full_sessions_per_month when under free limit" do
        assert Plans.check(:full_sessions_per_month, :free, 9) == :ok
      end

      test "returns {:error, :limit_reached} for full_sessions_per_month at free limit" do
        assert Plans.check(:full_sessions_per_month, :free, 10) == {:error, :limit_reached}
      end
    end
  end
  ```

- [x] **Step 2: Run the test to verify it fails**

  ```bash
  mix test test/speechwave/plans_test.exs
  ```

  Expected: compilation error — `Speechwave.Plans` does not exist.

- [x] **Step 3: Create `lib/speechwave/plans.ex`**

  ```elixir
  defmodule Speechwave.Plans do
    @moduledoc """
    Defines tier limits for each plan and provides enforcement checks.

    Plans: :free, :pro, :org
    Features: :max_participants, :full_sessions_per_month

    A "full session" is a session lasting longer than 10 minutes.
    """

    @type plan :: :free | :pro | :org
    @type feature :: :max_participants | :full_sessions_per_month
    @type limit :: non_neg_integer() | :unlimited

    @spec limit(feature(), plan()) :: limit()
    def limit(:max_participants, :free), do: 50
    def limit(:full_sessions_per_month, :free), do: 10
    def limit(:max_participants, :pro), do: :unlimited
    def limit(:full_sessions_per_month, :pro), do: :unlimited
    def limit(feature, :org), do: limit(feature, :pro)

    @spec check(feature(), plan(), non_neg_integer()) :: :ok | {:error, :limit_reached}
    def check(feature, plan, current_count) when is_integer(current_count) do
      case limit(feature, plan) do
        :unlimited -> :ok
        max when current_count < max -> :ok
        _ -> {:error, :limit_reached}
      end
    end
  end
  ```

- [x] **Step 4: Run the tests to verify they pass**

  ```bash
  mix test test/speechwave/plans_test.exs
  ```

  Expected: all tests pass.

- [x] **Step 5: Run the full test suite**

  ```bash
  mix test
  ```

  Expected: all tests pass, no regressions.

- [x] **Step 6: Commit**

  ```bash
  git add lib/speechwave/plans.ex test/speechwave/plans_test.exs
  git commit -m "feat: add Plans module with free/pro/org tier limits"
  git push
  ```

---

## Task 5: Precommit Check

- [x] **Step 1: Run precommit alias**

  ```bash
  mix precommit
  ```

  Expected: compiles without warnings, all tests pass, no unused deps, formatting clean.
