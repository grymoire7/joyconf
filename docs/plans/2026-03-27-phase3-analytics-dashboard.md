# Phase 3: Analytics Dashboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The admin panel gains a per-session analytics view showing reaction totals broken down by slide. Sessions from the same talk can be compared side-by-side so a speaker can see how audience engagement shifted between practice runs.

**Architecture:** A `Reactions.slide_reaction_totals/1` query aggregates reactions by slide and emoji. A new `SessionAnalyticsLive` LiveView at `/admin/sessions/:id` renders a Tailwind-based bar chart (no JS charting library). A comparison mode at `/admin/sessions/:id/compare/:other_id` renders two charts side-by-side. The admin sessions panel links to these views.

**Tech Stack:** Elixir/Phoenix, Ecto, ExUnit, Phoenix.LiveViewTest, Tailwind CSS

**Prerequisite:** Phase 1 must be complete before starting. Phase 2 is not required — slide `0` reactions just appear under a "General" label.

---

## File Map

**Create:**
- `lib/joyconf_web/live/session_analytics_live.ex` — analytics LiveView
- `lib/joyconf_web/live/session_analytics_live.html.heex` — analytics template
- `test/joyconf_web/live/session_analytics_live_test.exs` — analytics view tests

**Modify:**
- `lib/joyconf/reactions.ex` — add `slide_reaction_totals/1`
- `lib/joyconf_web/router.ex` — add analytics routes under `/admin`
- `lib/joyconf_web/live/admin_live.html.heex` — add "View Analytics" link per session
- `test/joyconf/reactions_test.exs` — add `slide_reaction_totals/1` tests

---

## Task 1: `slide_reaction_totals/1` Query

**Files:**
- Modify: `lib/joyconf/reactions.ex`
- Modify: `test/joyconf/reactions_test.exs`

This function returns a list of `%{slide_number, emoji, count}` maps for a session, ordered by slide number. The caller groups these by `slide_number` for display.

- [ ] **Step 1: Add query test**

Append to `test/joyconf/reactions_test.exs`:

```elixir
  describe "slide_reaction_totals/1" do
    test "returns per-slide per-emoji counts ordered by slide number", %{session: session} do
      Reactions.create_reaction(session, "❤️", 1)
      Reactions.create_reaction(session, "❤️", 1)
      Reactions.create_reaction(session, "😂", 1)
      Reactions.create_reaction(session, "❤️", 3)
      Reactions.create_reaction(session, "❤️", 0)

      totals = Reactions.slide_reaction_totals(session.id)

      # Ordered by slide number ascending
      assert Enum.map(totals, & &1.slide_number) == [0, 1, 1, 3]

      slide1_heart = Enum.find(totals, &(&1.slide_number == 1 and &1.emoji == "❤️"))
      assert slide1_heart.count == 2

      slide1_laugh = Enum.find(totals, &(&1.slide_number == 1 and &1.emoji == "😂"))
      assert slide1_laugh.count == 1
    end

    test "returns empty list for session with no reactions", %{session: session} do
      assert Reactions.slide_reaction_totals(session.id) == []
    end
  end
```

- [ ] **Step 2: Run test — confirm it fails**

```bash
mix test test/joyconf/reactions_test.exs
```

Expected: failure — `slide_reaction_totals/1` not defined.

- [ ] **Step 3: Add `slide_reaction_totals/1` to `lib/joyconf/reactions.ex`**

```elixir
  def slide_reaction_totals(session_id) do
    from(r in Reaction,
      where: r.talk_session_id == ^session_id,
      group_by: [r.slide_number, r.emoji],
      select: %{slide_number: r.slide_number, emoji: r.emoji, count: count(r.id)},
      order_by: [asc: r.slide_number]
    )
    |> Repo.all()
  end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/joyconf/reactions_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/joyconf/reactions.ex test/joyconf/reactions_test.exs
git commit -m "feat: add slide_reaction_totals query to Reactions context"
```

---

## Task 2: Analytics Route

**Files:**
- Modify: `lib/joyconf_web/router.ex`

- [ ] **Step 1: Add analytics routes to the admin scope**

In `lib/joyconf_web/router.ex`, in the `/admin` scope (around line 29), add:

```elixir
  scope "/admin", JoyconfWeb do
    pipe_through [:browser, :admin]
    live "/", AdminLive, :index
    live "/talks/new", AdminLive, :new
    live "/sessions/:id", SessionAnalyticsLive, :show
    live "/sessions/:id/compare/:other_id", SessionAnalyticsLive, :compare
  end
```

- [ ] **Step 2: Run the test suite to catch any router issues**

```bash
mix test
```

Expected: all existing tests pass (the new routes are unreachable until the LiveView module exists, but routing itself compiles).

- [ ] **Step 3: Commit**

```bash
git add lib/joyconf_web/router.ex
git commit -m "feat: add session analytics routes"
```

---

## Task 3: `SessionAnalyticsLive` — Single Session View

**Files:**
- Create: `lib/joyconf_web/live/session_analytics_live.ex`
- Create: `lib/joyconf_web/live/session_analytics_live.html.heex`
- Create: `test/joyconf_web/live/session_analytics_live_test.exs`

The view shows:
- Session label, talk title, start/end time
- Total reaction count
- Per-slide breakdown: each slide gets a row showing emoji counts as inline bars
- Slide `0` is labeled "General" (reactions received before any slide was tracked)
- A "Compare with another session" link if the talk has more than one session

Helper function `group_by_slide/1` converts the flat `slide_reaction_totals` list into a map of `slide_number => [%{emoji, count}]` for easy template iteration.

- [ ] **Step 1: Write the failing tests**

Create `test/joyconf_web/live/session_analytics_live_test.exs`:

```elixir
defmodule JoyconfWeb.SessionAnalyticsLiveTest do
  use JoyconfWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    Application.put_env(:joyconf, :admin_password, "testpassword")
    authed = put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:testpassword"))
    {:ok, conn: authed}
  end

  setup do
    {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    {:ok, session} = Joyconf.Talks.start_session(talk)
    {:ok, talk: talk, session: session}
  end

  test "renders session label and talk title", %{conn: conn, talk: talk, session: session} do
    {:ok, _view, html} = live(conn, "/admin/sessions/#{session.id}")
    assert html =~ session.label
    assert html =~ talk.title
  end

  test "shows total reaction count", %{conn: conn, session: session} do
    Joyconf.Reactions.create_reaction(session, "❤️", 1)
    Joyconf.Reactions.create_reaction(session, "😂", 1)
    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}")
    assert has_element?(view, "#total-reactions", "2")
  end

  test "renders a row for each slide that has reactions", %{conn: conn, session: session} do
    Joyconf.Reactions.create_reaction(session, "❤️", 1)
    Joyconf.Reactions.create_reaction(session, "❤️", 3)
    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}")
    assert has_element?(view, "#slide-row-1")
    assert has_element?(view, "#slide-row-3")
    refute has_element?(view, "#slide-row-2")
  end

  test "labels slide 0 as General", %{conn: conn, session: session} do
    Joyconf.Reactions.create_reaction(session, "❤️", 0)
    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}")
    assert has_element?(view, "#slide-row-0", "General")
  end

  test "shows compare link when talk has multiple sessions", %{conn: conn, talk: talk, session: session} do
    {:ok, s1} = Joyconf.Talks.stop_session(session)
    {:ok, s2} = Joyconf.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/admin/sessions/#{s1.id}")
    assert has_element?(view, "#compare-link")
  end

  test "redirects to admin when session id is unknown", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/sessions/999999")
  end

  test "redirects to admin for non-integer session id", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/sessions/notanumber")
  end

  test "renders compare section when compare_session param is present",
       %{conn: conn, talk: talk, session: session} do
    {:ok, _} = Joyconf.Talks.stop_session(session)
    {:ok, s2} = Joyconf.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}/compare/#{s2.id}")
    assert has_element?(view, "#compare-section")
    assert render(view) =~ session.label
    assert render(view) =~ s2.label
  end
end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/joyconf_web/live/session_analytics_live_test.exs
```

Expected: compile error — `SessionAnalyticsLive` not defined.

- [ ] **Step 3: Create `lib/joyconf_web/live/session_analytics_live.ex`**

```elixir
defmodule JoyconfWeb.SessionAnalyticsLive do
  use JoyconfWeb, :live_view

  alias Joyconf.{Talks, Reactions}

  def mount(%{"id" => id} = params, _session, socket) do
    session_id = case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end

    case session_id && Talks.get_session(session_id) do
      nil ->
        {:ok, redirect(socket, to: "/admin")}

      session ->
        talk = Talks.get_talk!(session.talk_id)
        totals = Reactions.slide_reaction_totals(session.id)
        by_slide = group_by_slide(totals)
        other_sessions = Talks.list_sessions(talk.id) |> Enum.reject(&(&1.session.id == session.id))

        compare_session =
          case params do
            %{"other_id" => other_id} -> Talks.get_session(String.to_integer(other_id))
            _ -> nil
          end

        compare_totals =
          if compare_session, do: group_by_slide(Reactions.slide_reaction_totals(compare_session.id)), else: %{}

        {:ok,
         assign(socket,
           session: session,
           talk: talk,
           by_slide: by_slide,
           total_reactions: Reactions.count_reactions(session.id),
           other_sessions: other_sessions,
           compare_session: compare_session,
           compare_by_slide: compare_totals
         )}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp group_by_slide(totals) do
    totals
    |> Enum.group_by(& &1.slide_number)
    |> Map.new(fn {slide, entries} ->
      {slide, Enum.map(entries, &%{emoji: &1.emoji, count: &1.count})}
    end)
  end
end
```

- [ ] **Step 4: Create `lib/joyconf_web/live/session_analytics_live.html.heex`**

```heex
<Layouts.app flash={@flash}>
  <div class="p-6 max-w-4xl mx-auto">
    <div class="mb-6">
      <a href="/admin" class="text-blue-400 hover:text-blue-300 text-sm">← Back to Admin</a>
      <h1 class="text-2xl font-bold mt-2">{@session.label}</h1>
      <p class="text-zinc-400">{@talk.title}</p>
      <p class="text-zinc-500 text-sm mt-1">
        {Calendar.strftime(@session.started_at, "%b %d, %Y %H:%M")}
        <%= if @session.ended_at do %>
          → {Calendar.strftime(@session.ended_at, "%H:%M")}
        <% else %>
          <span class="text-green-400">• Active</span>
        <% end %>
      </p>
    </div>

    <div class="flex items-center gap-4 mb-8">
      <div class="px-4 py-3 rounded-lg bg-zinc-800 border border-zinc-700">
        <div class="text-xs text-zinc-400 uppercase tracking-wide">Total Reactions</div>
        <div id="total-reactions" class="text-3xl font-bold">{@total_reactions}</div>
      </div>

      <%= if length(@other_sessions) > 0 do %>
        <div id="compare-link" class="text-sm">
          <span class="text-zinc-400">Compare with: </span>
          <%= for %{session: other} <- @other_sessions do %>
            <.link
              navigate={"/admin/sessions/#{@session.id}/compare/#{other.id}"}
              class="text-blue-400 hover:text-blue-300 mr-3"
            >
              {other.label}
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>

    <%= if @by_slide == %{} do %>
      <p class="text-zinc-500">No reactions recorded in this session.</p>
    <% else %>
      <div class="space-y-6">
        <%= for slide_number <- @by_slide |> Map.keys() |> Enum.sort() do %>
          <% entries = @by_slide[slide_number] %>
          <% max_count = entries |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end) %>
          <div id={"slide-row-#{slide_number}"} class="p-4 rounded-lg bg-zinc-800 border border-zinc-700">
            <div class="text-sm font-semibold text-zinc-300 mb-3">
              {if slide_number == 0, do: "General", else: "Slide #{slide_number}"}
            </div>
            <div class="space-y-2">
              <%= for %{emoji: emoji, count: count} <- Enum.sort_by(entries, & &1.count, :desc) do %>
                <div class="flex items-center gap-3">
                  <span class="text-xl w-8">{emoji}</span>
                  <div class="flex-1 bg-zinc-700 rounded-full h-4 overflow-hidden">
                    <div
                      class="h-full bg-blue-500 rounded-full transition-all"
                      style={"width: #{Float.round(count / max_count * 100, 1)}%"}
                    ></div>
                  </div>
                  <span class="text-zinc-300 text-sm w-8 text-right">{count}</span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>

    <%= if @compare_session do %>
      <% all_slides = (Map.keys(@by_slide) ++ Map.keys(@compare_by_slide)) |> Enum.uniq() |> Enum.sort() %>
      <div id="compare-section" class="mt-10 pt-8 border-t border-zinc-700">
        <h2 class="text-xl font-semibold mb-6">
          Comparing <span class="text-blue-300">{@session.label}</span>
          vs <span class="text-purple-300">{@compare_session.label}</span>
        </h2>
        <div class="grid grid-cols-2 gap-6">
          <%= for {slide_data, label_color} <- [{@by_slide, "text-blue-300"}, {@compare_by_slide, "text-purple-300"}] do %>
            <% session_label = if slide_data == @by_slide, do: @session.label, else: @compare_session.label %>
            <div>
              <h3 class={"font-medium mb-4 #{label_color}"}>{session_label}</h3>
              <div class="space-y-4">
                <%= for slide_number <- all_slides do %>
                  <% entries = Map.get(slide_data, slide_number, []) %>
                  <% max_count = entries |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end) %>
                  <div class="p-3 rounded-lg bg-zinc-800 border border-zinc-700">
                    <div class="text-xs font-semibold text-zinc-400 mb-2">
                      {if slide_number == 0, do: "General", else: "Slide #{slide_number}"}
                    </div>
                    <%= if entries == [] do %>
                      <div class="text-xs text-zinc-600">No reactions</div>
                    <% else %>
                      <%= for %{emoji: emoji, count: count} <- Enum.sort_by(entries, & &1.count, :desc) do %>
                        <div class="flex items-center gap-2 mb-1">
                          <span class="text-base w-6">{emoji}</span>
                          <div class="flex-1 bg-zinc-700 rounded-full h-3 overflow-hidden">
                            <div
                              class="h-full bg-blue-500 rounded-full"
                              style={"width: #{Float.round(count / max_count * 100, 1)}%"}
                            ></div>
                          </div>
                          <span class="text-zinc-300 text-xs w-6 text-right">{count}</span>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
</Layouts.app>
```

- [ ] **Step 5: Run tests — confirm they pass**

```bash
mix test test/joyconf_web/live/session_analytics_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 6: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/joyconf_web/live/session_analytics_live.ex \
        lib/joyconf_web/live/session_analytics_live.html.heex \
        test/joyconf_web/live/session_analytics_live_test.exs
git commit -m "feat: add SessionAnalyticsLive with per-slide breakdown and comparison"
```

---

## Task 4: Link to Analytics from the Admin Sessions Panel

**Files:**
- Modify: `lib/joyconf_web/live/admin_live.html.heex`
- Modify: `test/joyconf_web/live/admin_live_test.exs`

- [ ] **Step 1: Add analytics link test**

Append to `test/joyconf_web/live/admin_live_test.exs`:

```elixir
  test "sessions panel shows link to analytics for each session", %{conn: conn} do
    {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Analytics Talk", slug: "analytics-talk"})
    {:ok, session} = Joyconf.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/admin")
    view |> element("#talk-list button", "Analytics Talk") |> render_click()

    assert has_element?(view, "#analytics-link-#{session.id}")
  end
```

- [ ] **Step 2: Run test — confirm it fails**

```bash
mix test test/joyconf_web/live/admin_live_test.exs
```

Expected: failure — `#analytics-link-{id}` element not found.

- [ ] **Step 3: Add analytics link to `lib/joyconf_web/live/admin_live.html.heex`**

In the session list row, inside the non-renaming branch, add the analytics link after the Delete button:

```heex
                        <.link
                          id={"analytics-link-#{session.id}"}
                          navigate={"/admin/sessions/#{session.id}"}
                          class="text-xs text-zinc-400 hover:text-zinc-200 transition-colors"
                        >
                          Analytics
                        </.link>
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/joyconf_web/live/admin_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Run full test suite and precommit**

```bash
mix precommit
```

Expected: all checks pass.

- [ ] **Step 6: Commit**

```bash
git add lib/joyconf_web/live/admin_live.html.heex \
        test/joyconf_web/live/admin_live_test.exs
git commit -m "feat: add analytics links to admin sessions panel"
```

---

## Phase 3 Complete

The analytics dashboard is now live. Speakers can:

- Click "Analytics" next to any session in the admin panel to see per-slide reaction breakdowns.
- Use "Compare with" links to see two sessions side by side.
- Identify which slides generated the most engagement (or the most 💩) across practice runs.

Reactions that arrived before any slide was tracked (slide `0`) appear under "General" and are always included in the total count.
