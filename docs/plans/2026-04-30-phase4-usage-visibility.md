# Phase 4: Usage Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show users their current free-tier usage (sessions this month, participant cap) in the dashboard so they know where they stand against their plan limits.

**Architecture:** `DashboardLive.mount/3` calls the existing `Talks.count_full_sessions_this_month/1` and assigns the result alongside the plan limits (read from `Speechwave.Plans`). The dashboard template renders a usage summary section with a progress bar for sessions and a static participant cap badge. The confirmation-pending email banner (added in Phase 2) is already in place. No new database queries or schema changes are needed.

**Tech Stack:** Elixir, Phoenix LiveView, Tailwind CSS v4

---

## File Map

### Modified
| File | Change |
|---|---|
| `lib/speechwave_web/live/dashboard_live.ex` | Add `full_session_count`, `session_limit`, `participant_limit` assigns |
| `lib/speechwave_web/live/dashboard_live.html.heex` | Add usage summary section |
| `test/speechwave_web/live/dashboard_live_test.exs` | Add usage visibility tests |

---

## Task 1: Add usage assigns to DashboardLive

**Files:**
- Modify: `lib/speechwave_web/live/dashboard_live.ex`
- Modify: `test/speechwave_web/live/dashboard_live_test.exs`

- [ ] **Step 1: Write failing tests**

In `test/speechwave_web/live/dashboard_live_test.exs`, add a new describe block at the end:

```elixir
describe "usage summary" do
  test "shows session usage count and limit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")
    assert has_element?(view, "#usage-summary")
    assert has_element?(view, "#sessions-used")
    assert has_element?(view, "#session-limit")
  end

  test "shows 0 sessions used when user has no completed sessions", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")
    assert render(view) =~ "0"
  end

  test "reflects full sessions completed this month", %{conn: conn, user: user} do
    # Create a talk and a completed full session (> 10 min) for this user
    talk = Speechwave.TalksFixtures.talk_fixture(user)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
      talk_id: talk.id,
      label: "Full Session",
      started_at: now,
      ended_at: DateTime.add(now, 15 * 60, :second)
    })

    {:ok, view, _html} = live(conn, "/dashboard")
    assert has_element?(view, "#sessions-used", "1")
  end

  test "shows participant cap", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")
    assert has_element?(view, "#participant-limit")
  end
end
```

> **Note:** These tests require `Speechwave.TalksFixtures` to be imported in the test file. If not already imported, add `import Speechwave.TalksFixtures` to the test module.

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/speechwave_web/live/dashboard_live_test.exs --grep "usage summary"
```

Expected: Tests fail — `#usage-summary`, `#sessions-used`, `#session-limit`, `#participant-limit` elements don't exist yet.

- [ ] **Step 3: Update `DashboardLive.mount/3` to add usage assigns**

In `lib/speechwave_web/live/dashboard_live.ex`, update the `mount/3` function. Add these three assigns:

```elixir
def mount(_params, _session, socket) do
  scope = socket.assigns.current_scope
  user = scope.user

  {:ok,
   assign(socket,
     talks: Talks.list_talks(scope),
     form: to_form(Talk.changeset(%Talk{}, %{})),
     created_talk: nil,
     selected_talk: nil,
     selected_qr_data_uri: nil,
     sessions: [],
     renaming_session_id: nil,
     rename_form: nil,
     confirmed?: not is_nil(user.confirmed_at),
     full_session_count: Talks.count_full_sessions_this_month(scope),
     session_limit: Speechwave.Plans.limit(:full_sessions_per_month, user.plan),
     participant_limit: Speechwave.Plans.limit(:max_participants, user.plan)
   )}
end
```

Also add `alias Speechwave.Plans` at the top of the module alongside the existing aliases.

- [ ] **Step 4: Run the tests**

```bash
mix test test/speechwave_web/live/dashboard_live_test.exs --grep "usage summary"
```

Expected: The "shows session usage count" and "shows participant cap" tests now fail with a template error (the assigns exist but the elements don't). The "reflects full sessions" test may still fail. That's correct — you'll add the template in the next task.

- [ ] **Step 5: Commit the assign changes**

```bash
git add lib/speechwave_web/live/dashboard_live.ex
git commit -m "feat: add usage count and plan limit assigns to DashboardLive"
```

---

## Task 2: Add usage summary section to dashboard template

**Files:**
- Modify: `lib/speechwave_web/live/dashboard_live.html.heex`

- [ ] **Step 1: Add the usage summary section**

In `lib/speechwave_web/live/dashboard_live.html.heex`, add the usage summary section after the email confirmation banner and before the "Create a Talk" form. The exact location depends on the current template structure, but it should appear near the top of the page body:

```heex
<%!-- Usage Summary --%>
<div id="usage-summary" class="mb-6 p-5 bg-white rounded-xl border border-gray-200 shadow-sm">
  <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
    Plan Usage — Free
  </h2>
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">

    <%!-- Full sessions this month --%>
    <div>
      <div class="flex justify-between items-baseline mb-1.5">
        <span class="text-sm text-gray-700">Full sessions this month</span>
        <span class="text-sm font-semibold text-gray-900">
          <span id="sessions-used">{@full_session_count}</span>
          <span class="text-gray-400"> / </span>
          <span id="session-limit">
            <%= if @session_limit == :unlimited do %>
              ∞
            <% else %>
              {@session_limit}
            <% end %>
          </span>
        </span>
      </div>
      <%= if @session_limit != :unlimited do %>
        <div class="w-full bg-gray-100 rounded-full h-2 overflow-hidden">
          <div
            class={[
              "h-2 rounded-full transition-all",
              cond do
                @full_session_count >= @session_limit -> "bg-red-500"
                @full_session_count >= @session_limit * 0.8 -> "bg-amber-400"
                true -> "bg-indigo-500"
              end
            ]}
            style={"width: #{min(round(@full_session_count / @session_limit * 100), 100)}%"}
          >
          </div>
        </div>
        <%= if @full_session_count >= @session_limit do %>
          <p class="text-xs text-red-500 mt-1">Monthly limit reached. Sessions will be blocked until next month.</p>
        <% end %>
      <% end %>
      <p class="text-xs text-gray-400 mt-1">A "full session" is longer than 10 minutes.</p>
    </div>

    <%!-- Participant cap --%>
    <div>
      <div class="flex justify-between items-baseline mb-1.5">
        <span class="text-sm text-gray-700">Max participants per talk</span>
        <span id="participant-limit" class="text-sm font-semibold text-gray-900">
          <%= if @participant_limit == :unlimited do %>
            Unlimited
          <% else %>
            {@participant_limit}
          <% end %>
        </span>
      </div>
      <p class="text-xs text-gray-400 mt-1">Enforced per active talk connection.</p>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Run all dashboard tests**

```bash
mix test test/speechwave_web/live/dashboard_live_test.exs
```

Expected: All pass, including the usage summary tests.

- [ ] **Step 3: Start the server and verify the usage summary visually**

```bash
mix phx.server
```

Log in and open `http://localhost:4000/dashboard`. Verify:

- Usage summary section appears above the talk form
- "0 / 10" sessions used for a fresh account
- Progress bar is indigo at low usage
- Participant limit shows "50"
- Create a completed 15-minute session (insert directly via the dev console or seeds if needed) and reload to verify the count increments

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/live/dashboard_live.html.heex
git commit -m "feat: add usage summary section to dashboard"
```

---

## Task 3: Run full test suite and precommit

- [ ] **Step 1: Run all tests**

```bash
mix test
```

Expected: All pass, zero failures.

- [ ] **Step 2: Run precommit**

```bash
mix precommit
```

Fix any issues and commit:

```bash
git add -A && git commit -m "chore: precommit fixes for usage visibility"
```

Skip this commit if nothing changed.
