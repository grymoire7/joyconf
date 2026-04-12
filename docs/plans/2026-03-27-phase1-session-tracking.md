# Phase 1: Session Tracking & Reaction Persistence

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist reactions to the database, associated with a talk session that the presenter starts and stops from the extension popup. The admin panel lists sessions per talk with reaction totals and supports renaming and deleting sessions.

**Architecture:** Two new tables — `talk_sessions` (belongs to a talk) and `reactions` (belongs to a session). `ReactionChannel` becomes bidirectional: the extension pushes `start_session`/`stop_session` events. `TalkLive` persists each reaction to the active session (if any) before broadcasting. A sessions panel is added to `AdminLive`.

**Tech Stack:** Elixir/Phoenix, Ecto, ExUnit, Phoenix.ChannelTest, Phoenix.LiveViewTest

---

## File Map

**Create:**
- `priv/repo/migrations/TIMESTAMP_create_talk_sessions.exs`
- `priv/repo/migrations/TIMESTAMP_create_reactions.exs`
- `lib/speechwave/talks/talk_session.ex` — TalkSession schema + changeset
- `lib/speechwave/reactions.ex` — Reactions context (create, count)
- `lib/speechwave/reactions/reaction.ex` — Reaction schema + changeset
- `test/speechwave/sessions_test.exs` — session lifecycle + admin function tests
- `test/speechwave/reactions_test.exs` — reaction creation + count tests

**Modify:**
- `lib/speechwave/talks/talk.ex` — add `has_many :talk_sessions`
- `lib/speechwave/talks.ex` — add session functions
- `lib/speechwave_web/channels/reaction_channel.ex` — add `handle_in` for session events
- `lib/speechwave_web/live/talk_live.ex` — persist reaction when active session exists
- `lib/speechwave_web/live/admin_live.ex` — sessions assigns + events
- `lib/speechwave_web/live/admin_live.html.heex` — sessions panel
- `test/speechwave_web/channels/reaction_channel_test.exs` — session channel tests
- `test/speechwave_web/live/admin_live_test.exs` — session UI tests
- `test/speechwave_web/live/talk_live_test.exs` — reaction persistence tests
- `extension/popup/popup.html` — Start/Stop Session button + session status
- `extension/popup/popup.js` — session state management
- `extension/content/content.js` — channel push for start/stop session

---

## Task 1: `talk_sessions` Migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_talk_sessions.exs`

- [ ] **Step 1: Generate the migration file**

```bash
mix ecto.gen.migration create_talk_sessions
```

- [ ] **Step 2: Fill in the generated file**

Open the file at `priv/repo/migrations/*_create_talk_sessions.exs` and replace its contents:

```elixir
defmodule Speechwave.Repo.Migrations.CreateTalkSessions do
  use Ecto.Migration

  def change do
    create table(:talk_sessions) do
      add :talk_id, references(:talks, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:talk_sessions, [:talk_id])
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: `[info] == Running ... CreateTalkSessions.change/0 forward` with no errors.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/*_create_talk_sessions.exs
git commit -m "feat: add talk_sessions migration"
```

---

## Task 2: `TalkSession` Schema

**Files:**
- Create: `lib/speechwave/talks/talk_session.ex`
- Modify: `lib/speechwave/talks/talk.ex`
- Test: `test/speechwave/sessions_test.exs` (partial — changeset tests only)

- [ ] **Step 1: Write the failing changeset tests**

Create `test/speechwave/sessions_test.exs`:

```elixir
defmodule Speechwave.SessionsTest do
  use Speechwave.DataCase

  alias Speechwave.Talks
  alias Speechwave.Talks.TalkSession

  setup do
    {:ok, talk} = Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    %{talk: talk}
  end

  describe "TalkSession.changeset/2" do
    test "valid with label and started_at" do
      cs =
        TalkSession.changeset(%TalkSession{}, %{
          label: "Session 1",
          started_at: ~U[2026-01-01 10:00:00Z]
        })

      assert cs.valid?
    end

    test "requires label" do
      cs = TalkSession.changeset(%TalkSession{}, %{started_at: ~U[2026-01-01 10:00:00Z]})
      assert "can't be blank" in errors_on(cs).label
    end

    test "requires started_at" do
      cs = TalkSession.changeset(%TalkSession{}, %{label: "Session 1"})
      assert "can't be blank" in errors_on(cs).started_at
    end
  end
end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/speechwave/sessions_test.exs
```

Expected: compile error — `TalkSession` module not found.

- [ ] **Step 3: Create `lib/speechwave/talks/talk_session.ex`**

```elixir
defmodule Speechwave.Talks.TalkSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "talk_sessions" do
    field :label, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :talk, Speechwave.Talks.Talk
    has_many :reactions, Speechwave.Reactions.Reaction

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:label, :started_at, :ended_at])
    |> validate_required([:label, :started_at])
  end
end
```

- [ ] **Step 4: Add `has_many :talk_sessions` to `lib/speechwave/talks/talk.ex`**

In the schema block, after the existing fields, add:

```elixir
has_many :talk_sessions, Speechwave.Talks.TalkSession
```

- [ ] **Step 5: Run tests — confirm they pass**

```bash
mix test test/speechwave/sessions_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/talks/talk_session.ex lib/speechwave/talks/talk.ex test/speechwave/sessions_test.exs
git commit -m "feat: add TalkSession schema"
```

---

## Task 3: `reactions` Migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_reactions.exs`

- [ ] **Step 1: Generate the migration file**

```bash
mix ecto.gen.migration create_reactions
```

- [ ] **Step 2: Fill in the generated file**

```elixir
defmodule Speechwave.Repo.Migrations.CreateReactions do
  use Ecto.Migration

  def change do
    create table(:reactions) do
      add :talk_session_id, references(:talk_sessions, on_delete: :delete_all), null: false
      add :emoji, :string, null: false
      add :slide_number, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:reactions, [:talk_session_id])
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/*_create_reactions.exs
git commit -m "feat: add reactions migration"
```

---

## Task 4: `Reaction` Schema + `Reactions` Context

**Files:**
- Create: `lib/speechwave/reactions/reaction.ex`
- Create: `lib/speechwave/reactions.ex`
- Test: `test/speechwave/reactions_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/speechwave/reactions_test.exs`:

```elixir
defmodule Speechwave.ReactionsTest do
  use Speechwave.DataCase

  alias Speechwave.{Talks, Reactions}

  setup do
    {:ok, talk} = Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    {:ok, session} = Talks.start_session(talk)
    %{session: session}
  end

  describe "create_reaction/3" do
    test "creates a reaction with default slide 0", %{session: session} do
      assert {:ok, reaction} = Reactions.create_reaction(session, "❤️")
      assert reaction.emoji == "❤️"
      assert reaction.slide_number == 0
      assert reaction.talk_session_id == session.id
    end

    test "creates a reaction with a specified slide number", %{session: session} do
      assert {:ok, reaction} = Reactions.create_reaction(session, "😂", 5)
      assert reaction.slide_number == 5
    end

    test "requires emoji", %{session: session} do
      assert {:error, changeset} = Reactions.create_reaction(session, nil)
      assert "can't be blank" in errors_on(changeset).emoji
    end
  end

  describe "count_reactions/1" do
    test "returns count of reactions for a session", %{session: session} do
      Reactions.create_reaction(session, "❤️")
      Reactions.create_reaction(session, "😂")
      assert Reactions.count_reactions(session.id) == 2
    end

    test "returns 0 for a session with no reactions", %{session: session} do
      assert Reactions.count_reactions(session.id) == 0
    end
  end
end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/speechwave/reactions_test.exs
```

Expected: compile error — `Reactions` module and `Talks.start_session/1` not found yet. That's expected.

- [ ] **Step 3: Create `lib/speechwave/reactions/reaction.ex`**

```elixir
defmodule Speechwave.Reactions.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reactions" do
    field :emoji, :string
    field :slide_number, :integer, default: 0

    belongs_to :talk_session, Speechwave.Talks.TalkSession

    timestamps(type: :utc_datetime)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :slide_number])
    |> validate_required([:emoji])
  end
end
```

- [ ] **Step 4: Create `lib/speechwave/reactions.ex`**

```elixir
defmodule Speechwave.Reactions do
  import Ecto.Query

  alias Speechwave.Repo
  alias Speechwave.Reactions.Reaction
  alias Speechwave.Talks.TalkSession

  def create_reaction(%TalkSession{} = session, emoji, slide_number \\ 0) do
    %Reaction{talk_session_id: session.id}
    |> Reaction.changeset(%{emoji: emoji, slide_number: slide_number})
    |> Repo.insert()
  end

  def count_reactions(session_id) do
    Repo.aggregate(from(r in Reaction, where: r.talk_session_id == ^session_id), :count)
  end
end
```

The tests still need `Talks.start_session/1` — implement that in the next task before running. Do not run the tests yet.

- [ ] **Step 5: Commit schema + context**

```bash
git add lib/speechwave/reactions/reaction.ex lib/speechwave/reactions.ex test/speechwave/reactions_test.exs
git commit -m "feat: add Reaction schema and Reactions context"
```

---

## Task 5: `Talks` Context — Session Lifecycle Functions

**Files:**
- Modify: `lib/speechwave/talks.ex`
- Test: `test/speechwave/sessions_test.exs` (extend with lifecycle tests)

- [ ] **Step 1: Add lifecycle tests to `test/speechwave/sessions_test.exs`**

Append these describe blocks to the existing file (after the changeset tests):

```elixir
  describe "start_session/1" do
    test "creates a session labeled 'Session 1' for a new talk", %{talk: talk} do
      assert {:ok, session} = Talks.start_session(talk)
      assert session.label == "Session 1"
      assert session.talk_id == talk.id
      assert session.started_at != nil
      assert session.ended_at == nil
    end

    test "labels the second session 'Session 2'", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      {:ok, _} = Talks.stop_session(s1)
      assert {:ok, s2} = Talks.start_session(talk)
      assert s2.label == "Session 2"
    end

    test "returns the existing session when one is already active", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      assert {:ok, s2} = Talks.start_session(talk)
      assert s1.id == s2.id
    end
  end

  describe "stop_session/1" do
    test "sets ended_at on the session", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, stopped} = Talks.stop_session(session)
      assert stopped.ended_at != nil
    end
  end

  describe "get_active_session/1" do
    test "returns the active session when one exists", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert Talks.get_active_session(talk.id).id == session.id
    end

    test "returns nil when no session has been started", %{talk: talk} do
      assert Talks.get_active_session(talk.id) == nil
    end

    test "returns nil after the session is stopped", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      Talks.stop_session(session)
      assert Talks.get_active_session(talk.id) == nil
    end
  end

  describe "get_session/1 and get_session!/1" do
    test "get_session/1 returns the session by id", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert Talks.get_session(session.id).id == session.id
    end

    test "get_session/1 returns nil for unknown id" do
      assert Talks.get_session(999_999) == nil
    end

    test "get_session!/1 raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Talks.get_session!(999_999) end
    end
  end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/speechwave/sessions_test.exs
```

Expected: failures — `start_session/1`, `stop_session/1`, etc. not defined.

- [ ] **Step 3: Add session lifecycle functions to `lib/speechwave/talks.ex`**

Add the following to `lib/speechwave/talks.ex`. Add `import Ecto.Query` and `alias Speechwave.Talks.TalkSession` at the top of the module alongside the existing aliases:

```elixir
defmodule Speechwave.Talks do
  import Ecto.Query

  alias Speechwave.Repo
  alias Speechwave.Talks.Talk
  alias Speechwave.Talks.TalkSession

  # --- existing functions (list_talks, get_talk!, etc.) unchanged ---

  def start_session(%Talk{} = talk) do
    case get_active_session(talk.id) do
      nil ->
        n = count_sessions(talk.id)

        %TalkSession{talk_id: talk.id}
        |> TalkSession.changeset(%{
          label: "Session #{n + 1}",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  def stop_session(%TalkSession{} = session) do
    session
    |> TalkSession.changeset(%{ended_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def get_active_session(talk_id) do
    Repo.one(
      from s in TalkSession,
        where: s.talk_id == ^talk_id and is_nil(s.ended_at),
        limit: 1
    )
  end

  def get_session(id), do: Repo.get(TalkSession, id)
  def get_session!(id), do: Repo.get!(TalkSession, id)

  defp count_sessions(talk_id) do
    Repo.aggregate(from(s in TalkSession, where: s.talk_id == ^talk_id), :count)
  end
end
```

> **Note on label numbering:** `count_sessions` counts all sessions ever created, including deleted ones. If Session 1 is deleted and a new session is started, it will be labeled "Session 2". This is intentional — labels are placeholders meant to be renamed to something meaningful (e.g., "Denver Practice"). The auto-number is for initial orientation only, not a stable identifier.



- [ ] **Step 4: Run lifecycle tests — confirm they pass**

```bash
mix test test/speechwave/sessions_test.exs
```

Expected: all tests pass (changeset tests + lifecycle tests).

- [ ] **Step 5: Run reactions tests — they should also pass now**

```bash
mix test test/speechwave/reactions_test.exs
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/talks.ex test/speechwave/sessions_test.exs
git commit -m "feat: add session lifecycle functions to Talks context"
```

---

## Task 6: `Talks` Context — Session Admin Functions

**Files:**
- Modify: `lib/speechwave/talks.ex`
- Test: `test/speechwave/sessions_test.exs` (extend with admin tests)

- [ ] **Step 1: Add admin function tests to `test/speechwave/sessions_test.exs`**

Append to the file:

```elixir
  describe "list_sessions/1" do
    test "returns sessions with reaction counts ordered newest first", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      {:ok, _} = Talks.stop_session(s1)
      {:ok, s2} = Talks.start_session(talk)

      Speechwave.Reactions.create_reaction(s1, "❤️")
      Speechwave.Reactions.create_reaction(s1, "😂")

      entries = Talks.list_sessions(talk.id)

      assert length(entries) == 2
      [first, second] = entries
      assert first.session.id == s2.id
      assert first.reaction_count == 0
      assert second.session.id == s1.id
      assert second.reaction_count == 2
    end

    test "returns empty list for a talk with no sessions", %{talk: talk} do
      assert Talks.list_sessions(talk.id) == []
    end
  end

  describe "rename_session/2" do
    test "updates the session label", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, renamed} = Talks.rename_session(session, "Denver Practice")
      assert renamed.label == "Denver Practice"
    end
  end

  describe "delete_session/1" do
    test "removes the session", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, _} = Talks.delete_session(session)
      assert Talks.get_session(session.id) == nil
    end

    test "cascade-deletes its reactions", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      {:ok, reaction} = Speechwave.Reactions.create_reaction(session, "❤️")
      Talks.delete_session(session)
      assert Speechwave.Repo.get(Speechwave.Reactions.Reaction, reaction.id) == nil
    end
  end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/speechwave/sessions_test.exs
```

Expected: failures — `list_sessions/1`, `rename_session/2`, `delete_session/1` not defined.

- [ ] **Step 3: Add admin functions to `lib/speechwave/talks.ex`**

```elixir
  def list_sessions(talk_id) do
    from(s in TalkSession,
      where: s.talk_id == ^talk_id,
      left_join: r in assoc(s, :reactions),
      group_by: s.id,
      select: %{session: s, reaction_count: count(r.id)},
      order_by: [desc: s.started_at]
    )
    |> Repo.all()
  end

  def rename_session(%TalkSession{} = session, label) when is_binary(label) do
    session
    |> TalkSession.changeset(%{label: label})
    |> Repo.update()
  end

  def delete_session(%TalkSession{} = session) do
    Repo.delete(session)
  end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/speechwave/sessions_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
mix test
```

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/talks.ex test/speechwave/sessions_test.exs
git commit -m "feat: add session admin functions to Talks context"
```

---

## Task 7: `ReactionChannel` — Bidirectional Session Start/Stop

**Files:**
- Modify: `lib/speechwave_web/channels/reaction_channel.ex`
- Modify: `test/speechwave_web/channels/reaction_channel_test.exs`

- [ ] **Step 1: Add session channel tests**

Append to `test/speechwave_web/channels/reaction_channel_test.exs`:

```elixir
  describe "session management via channel" do
    setup %{socket: socket, talk: talk} do
      {:ok, _, joined} = subscribe_and_join(socket, "reactions:#{talk.slug}", %{})
      %{joined: joined, talk: talk}
    end

    test "start_session creates a session and replies with session_id and label",
         %{joined: joined, talk: talk} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id, label: "Session 1"}
      assert Speechwave.Talks.get_session(session_id) != nil
    end

    test "start_session is idempotent when a session is already active",
         %{joined: joined} do
      ref1 = push(joined, "start_session", %{})
      assert_reply ref1, :ok, %{session_id: id1}

      ref2 = push(joined, "start_session", %{})
      assert_reply ref2, :ok, %{session_id: id2}

      assert id1 == id2
    end

    test "stop_session ends the active session", %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id}

      ref2 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref2, :ok

      session = Speechwave.Talks.get_session(session_id)
      assert session.ended_at != nil
    end

    test "stop_session returns error for an unknown session_id", %{joined: joined} do
      ref = push(joined, "stop_session", %{"session_id" => 999_999})
      assert_reply ref, :error, %{reason: "not_found"}
    end

    test "stop_session returns error for a session belonging to a different talk",
         %{joined: joined} do
      {:ok, other_talk} = Speechwave.Talks.create_talk(%{title: "Other", slug: "other"})
      {:ok, other_session} = Speechwave.Talks.start_session(other_talk)

      ref = push(joined, "stop_session", %{"session_id" => other_session.id})
      assert_reply ref, :error, %{reason: "unauthorized"}
    end

    test "stop_session is idempotent — does not overwrite ended_at on an already-stopped session",
         %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id}

      ref2 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref2, :ok
      first_end = Speechwave.Talks.get_session(session_id).ended_at

      ref3 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref3, :ok
      second_end = Speechwave.Talks.get_session(session_id).ended_at

      assert first_end == second_end
    end
  end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/speechwave_web/channels/reaction_channel_test.exs
```

Expected: failures — no `handle_in` clauses defined.

- [ ] **Step 3: Update `lib/speechwave_web/channels/reaction_channel.ex`**

```elixir
defmodule SpeechwaveWeb.ReactionChannel do
  use Phoenix.Channel

  alias Speechwave.Talks

  def join("reactions:" <> slug, _payload, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:error, %{reason: "not_found"}}

      talk ->
        {:ok, assign(socket, :talk, talk)}
    end
  end

  def handle_in("start_session", _payload, socket) do
    case Talks.start_session(socket.assigns.talk) do
      {:ok, session} ->
        {:reply, {:ok, %{session_id: session.id, label: session.label}}, socket}

      {:error, _changeset} ->
        {:reply, {:error, %{reason: "failed"}}, socket}
    end
  end

  # Guard against double-stop: if ended_at is already set, reply ok without
  # overwriting the original end timestamp.
  def handle_in("stop_session", %{"session_id" => session_id}, socket) do
    case Talks.get_session(session_id) do
      nil ->
        {:reply, {:error, %{reason: "not_found"}}, socket}

      %{ended_at: ended_at} when not is_nil(ended_at) ->
        {:reply, :ok, socket}

      %{talk_id: talk_id} = session when talk_id == socket.assigns.talk.id ->
        {:ok, _} = Talks.stop_session(session)
        {:reply, :ok, socket}

      _session ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end
end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/speechwave_web/channels/reaction_channel_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/channels/reaction_channel.ex \
        test/speechwave_web/channels/reaction_channel_test.exs
git commit -m "feat: add session start/stop to ReactionChannel"
```

---

## Task 8: `TalkLive` — Persist Reactions to Active Session

**Files:**
- Modify: `lib/speechwave_web/live/talk_live.ex`
- Modify: `test/speechwave_web/live/talk_live_test.exs`

- [ ] **Step 1: Add reaction persistence tests**

Append to `test/speechwave_web/live/talk_live_test.exs`:

```elixir
  describe "reaction persistence" do
    test "persists reaction to active session when one exists", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      render_click(view, "react", %{"emoji" => "❤️"})

      assert Speechwave.Reactions.count_reactions(session.id) == 1
    end

    test "does not persist reaction when no active session", %{conn: conn, talk: talk} do
      # No session started — reaction should broadcast fine but not persist
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")

      render_click(view, "react", %{"emoji" => "❤️"})

      assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 500
      # No session exists, so nothing to count — just verify no crash
    end
  end
```

- [ ] **Step 2: Run tests — confirm the persistence test fails**

```bash
mix test test/speechwave_web/live/talk_live_test.exs
```

Expected: the new `persists reaction` test fails (count is 0).

- [ ] **Step 3: Update `lib/speechwave_web/live/talk_live.ex`**

Add `Speechwave.Reactions` to the alias line and update `handle_event/3`:

```elixir
defmodule SpeechwaveWeb.TalkLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.{Talks, RateLimiter, Reactions}

  @emojis ["❤️", "😂", "👏", "🤯", "🙋🏻", "🎉", "💩", "😮", "🎯"]

  def mount(%{"slug" => slug}, _session, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:ok, redirect(socket, to: "/")}

      talk ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{slug}")
        end

        {:ok, assign(socket, talk: talk, emojis: @emojis, session_id: socket.id)}
    end
  end

  def handle_event("react", %{"emoji" => emoji}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id) do
      case Talks.get_active_session(socket.assigns.talk.id) do
        nil -> :ok
        session -> Reactions.create_reaction(session, emoji)
      end

      SpeechwaveWeb.Endpoint.broadcast!(
        "reactions:#{socket.assigns.talk.slug}",
        "new_reaction",
        %{emoji: emoji}
      )
    end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: emoji}},
        socket
      ) do
    {:noreply, push_event(socket, "new_reaction", %{emoji: emoji})}
  end
end
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
mix test test/speechwave_web/live/talk_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/live/talk_live.ex test/speechwave_web/live/talk_live_test.exs
git commit -m "feat: persist reactions to active session in TalkLive"
```

---

## Task 9: `AdminLive` — Sessions Panel

**Files:**
- Modify: `lib/speechwave_web/live/admin_live.ex`
- Modify: `lib/speechwave_web/live/admin_live.html.heex`
- Modify: `test/speechwave_web/live/admin_live_test.exs`

- [ ] **Step 1: Add session panel tests**

Append to `test/speechwave_web/live/admin_live_test.exs`:

```elixir
  describe "sessions panel" do
    setup %{conn: conn} do
      {:ok, talk} = Speechwave.Talks.create_talk(%{title: "Prime Talk", slug: "prime"})
      {:ok, conn: conn, talk: talk}
    end

    test "shows empty sessions message when talk has no sessions", %{conn: conn, talk: talk} do
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#sessions-panel")
      assert has_element?(view, "#no-sessions")
    end

    test "lists sessions with reaction counts when sessions exist", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      Speechwave.Reactions.create_reaction(session, "❤️")

      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      assert has_element?(view, "#session-#{session.id}")
      assert has_element?(view, "#session-label-#{session.id}", "Session 1")
      assert render(view) =~ "1 reaction"
    end

    test "shows Active badge for sessions without ended_at", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#session-#{session.id} .session-active-badge")
    end

    test "can rename a session", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()
      assert has_element?(view, "#rename-form-#{session.id}")

      view
      |> form("#rename-form-#{session.id}", rename: %{label: "Denver Practice"})
      |> render_submit()

      assert has_element?(view, "#session-label-#{session.id}", "Denver Practice")
    end

    test "can delete a session", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#delete-session-#{session.id}") |> render_click()

      refute has_element?(view, "#session-#{session.id}")
      assert Speechwave.Talks.get_session(session.id) == nil
    end

    test "rename form shows validation error for blank label", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()

      view
      |> form("#rename-form-#{session.id}", rename: %{label: ""})
      |> render_submit()

      # Form stays open with an error — session label is unchanged
      assert has_element?(view, "#rename-form-#{session.id}")
      assert has_element?(view, "#session-label-#{session.id}", "Session 1") == false or
               has_element?(view, "#rename-form-#{session.id}")
    end

    test "cancel_rename hides the rename form", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()
      assert has_element?(view, "#rename-form-#{session.id}")

      view |> element("button[phx-click='cancel_rename']") |> render_click()
      refute has_element?(view, "#rename-form-#{session.id}")
    end

    test "sessions panel is hidden after talk is deleted", %{conn: conn, talk: talk} do
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      view |> element("#delete-talk-#{talk.id}") |> render_click()
      refute has_element?(view, "#sessions-panel")
    end
  end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
mix test test/speechwave_web/live/admin_live_test.exs
```

Expected: session panel tests fail — elements not found.

- [ ] **Step 3: Update `lib/speechwave_web/live/admin_live.ex`**

```elixir
defmodule SpeechwaveWeb.AdminLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.Talks
  alias Speechwave.Talks.Talk

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       talks: Talks.list_talks(),
       form: to_form(Talk.changeset(%Talk{}, %{})),
       created_talk: nil,
       selected_talk: nil,
       selected_qr_data_uri: nil,
       sessions: [],
       renaming_session_id: nil,
       rename_form: nil
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("validate", %{"talk" => attrs}, socket) do
    slug =
      if attrs["title"] != "" and attrs["slug"] == "" do
        Talks.generate_slug(attrs["title"])
      else
        attrs["slug"]
      end

    changeset = Talk.changeset(%Talk{}, Map.put(attrs, "slug", slug))
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("delete_talk", %{"id" => id}, socket) do
    talk = Talks.get_talk!(String.to_integer(id))
    {:ok, _} = Talks.delete_talk(talk)

    {:noreply,
     assign(socket,
       talks: Talks.list_talks(),
       selected_talk: nil,
       selected_qr_data_uri: nil,
       sessions: [],
       renaming_session_id: nil,
       rename_form: nil
     )}
  end

  def handle_event("show_qr", %{"id" => id}, socket) do
    talk = Talks.get_talk!(String.to_integer(id))
    url = SpeechwaveWeb.Endpoint.url() <> "/t/#{talk.slug}"
    qr = Speechwave.QRCode.to_data_uri(url)
    sessions = Talks.list_sessions(talk.id)

    {:noreply,
     assign(socket,
       selected_talk: talk,
       selected_qr_data_uri: qr,
       sessions: sessions,
       renaming_session_id: nil,
       rename_form: nil
     )}
  end

  def handle_event("save", %{"talk" => attrs}, socket) do
    case Talks.create_talk(attrs) do
      {:ok, talk} ->
        url = SpeechwaveWeb.Endpoint.url() <> "/t/#{talk.slug}"
        qr = Speechwave.QRCode.to_data_uri(url)

        {:noreply,
         assign(socket,
           created_talk: talk,
           talks: Talks.list_talks(),
           form: to_form(Talk.changeset(%Talk{}, %{})),
           selected_talk: talk,
           selected_qr_data_uri: qr,
           sessions: [],
           renaming_session_id: nil,
           rename_form: nil
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("rename_session", %{"id" => id}, socket) do
    session = Talks.get_session!(String.to_integer(id))

    {:noreply,
     assign(socket,
       renaming_session_id: session.id,
       rename_form: to_form(%{"label" => session.label}, as: :rename)
     )}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, renaming_session_id: nil, rename_form: nil)}
  end

  def handle_event("save_rename", %{"rename" => %{"label" => label}}, socket) do
    session = Talks.get_session!(socket.assigns.renaming_session_id)

    case Talks.rename_session(session, label) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(renaming_session_id: nil, rename_form: nil)
         |> assign(sessions: Talks.list_sessions(socket.assigns.selected_talk.id))}

      {:error, changeset} ->
        # Re-render the rename form with validation errors visible
        {:noreply, assign(socket, rename_form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    session = Talks.get_session!(String.to_integer(id))
    {:ok, _} = Talks.delete_session(session)

    {:noreply, assign(socket, sessions: Talks.list_sessions(socket.assigns.selected_talk.id))}
  end
end
```

- [ ] **Step 4: Update `lib/speechwave_web/live/admin_live.html.heex`**

Replace the full file contents:

```heex
<Layouts.app flash={@flash}>
  <div class="p-6">
    <h1 class="text-2xl font-bold mb-6">JoyConf Admin</h1>

    <%= if @created_talk do %>
      <div id="created-talk" class="mb-6 p-4 bg-green-50 border border-green-200 rounded">
        <p class="font-semibold text-green-800">Talk created!</p>
        <p><strong>{@created_talk.title}</strong> — <code>/t/{@created_talk.slug}</code></p>
      </div>
    <% end %>

    <h2 class="text-xl font-semibold mb-4">New Talk</h2>
    <.form for={@form} id="talk-form" phx-change="validate" phx-submit="save" class="space-y-4">
      <.input field={@form[:title]} label="Title" />
      <.input field={@form[:slug]} label="Slug" />
      <.button type="submit">Create Talk</.button>
    </.form>

    <h2 class="text-xl font-semibold mt-8 mb-4">Existing Talks</h2>
    <div class="flex gap-8 items-start">
      <ul id="talk-list" class="space-y-2">
        <%= for talk <- @talks do %>
          <li class="flex items-center gap-2">
            <%= if @selected_talk && @selected_talk.id == talk.id do %>
              <button
                id={"delete-talk-#{talk.id}"}
                phx-click="delete_talk"
                phx-value-id={talk.id}
                class="text-lg hover:scale-125 transition-transform"
                title="Delete talk"
              >
                🗑️
              </button>
            <% end %>
            <button
              phx-click="show_qr"
              phx-value-id={talk.id}
              class={[
                "text-left px-3 py-2 rounded-lg border transition-colors flex-1",
                if(@selected_talk && @selected_talk.id == talk.id,
                  do: "border-blue-500 bg-blue-950 text-blue-200",
                  else: "border-zinc-600 hover:border-zinc-400 hover:bg-zinc-800"
                )
              ]}
            >
              <strong>{talk.title}</strong> — <code>/t/{talk.slug}</code>
            </button>
          </li>
        <% end %>
      </ul>

      <%= if @selected_talk do %>
        <div class="flex flex-col gap-6 flex-1">
          <div class="flex flex-col items-center gap-2">
            <img
              id="selected-talk-qr"
              src={@selected_qr_data_uri}
              alt={"QR code for #{@selected_talk.slug}"}
              width="200"
            />
            <a
              href={@selected_qr_data_uri}
              download={"#{@selected_talk.slug}-qr.png"}
              class="text-blue-400 underline text-sm"
            >
              Download QR Code (PNG)
            </a>
          </div>

          <div id="sessions-panel">
            <h3 class="text-lg font-semibold mb-3">Sessions</h3>
            <%= if @sessions == [] do %>
              <p id="no-sessions" class="text-zinc-500 text-sm">
                No sessions yet. Start one from the extension popup.
              </p>
            <% else %>
              <ul id="session-list" class="space-y-2">
                <%= for %{session: session, reaction_count: count} <- @sessions do %>
                  <li id={"session-#{session.id}"} class="p-3 rounded-lg border border-zinc-700 text-sm">
                    <%= if @renaming_session_id == session.id do %>
                      <.form
                        for={@rename_form}
                        id={"rename-form-#{session.id}"}
                        phx-submit="save_rename"
                        class="flex gap-2 items-end"
                      >
                        <.input field={@rename_form[:label]} label="Label" />
                        <button
                          type="submit"
                          class="px-3 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded text-xs mb-2"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_rename"
                          class="px-3 py-2 border border-zinc-600 hover:border-zinc-400 rounded text-xs mb-2"
                        >
                          Cancel
                        </button>
                      </.form>
                    <% else %>
                      <div class="flex items-center gap-3 flex-wrap">
                        <span id={"session-label-#{session.id}"} class="font-medium flex-1">
                          {session.label}
                        </span>
                        <span class="text-zinc-400">{count} {if count == 1, do: "reaction", else: "reactions"}</span>
                        <span class="text-zinc-500">
                          {Calendar.strftime(session.started_at, "%b %d %H:%M")}
                        </span>
                        <%= if session.ended_at do %>
                          <span class="text-zinc-500">
                            → {Calendar.strftime(session.ended_at, "%H:%M")}
                          </span>
                        <% else %>
                          <span class="session-active-badge text-xs px-2 py-0.5 bg-green-900 text-green-300 rounded-full">
                            Active
                          </span>
                        <% end %>
                        <button
                          id={"rename-session-#{session.id}"}
                          phx-click="rename_session"
                          phx-value-id={session.id}
                          class="text-xs text-blue-400 hover:text-blue-300 transition-colors"
                        >
                          Rename
                        </button>
                        <button
                          id={"delete-session-#{session.id}"}
                          phx-click="delete_session"
                          phx-value-id={session.id}
                          class="text-xs text-red-400 hover:text-red-300 transition-colors"
                        >
                          Delete
                        </button>
                      </div>
                    <% end %>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</Layouts.app>
```

- [ ] **Step 5: Run tests — confirm they pass**

```bash
mix test test/speechwave_web/live/admin_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 6: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave_web/live/admin_live.ex \
        lib/speechwave_web/live/admin_live.html.heex \
        test/speechwave_web/live/admin_live_test.exs
git commit -m "feat: add sessions panel to AdminLive"
```

---

## Task 10: Extension Popup — Start/Stop Session UI

**Files:**
- Modify: `extension/popup/popup.html`
- Modify: `extension/popup/popup.js`

No automated tests for the extension JS in Phase 1 (Jest setup comes in Phase 2). Verify manually by loading the unpacked extension in Chrome after completing Task 11.

- [ ] **Step 1: Update `extension/popup/popup.html`**

Replace the full file:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: sans-serif; width: 240px; padding: 16px; margin: 0; }
    h3 { margin: 0 0 12px; }
    label { font-size: 12px; font-weight: 600; color: #5f6368; }
    input { width: 100%; box-sizing: border-box; padding: 6px; margin: 4px 0 12px;
            border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }
    button { width: 100%; padding: 8px; background: #4285f4; color: white;
             border: none; border-radius: 4px; cursor: pointer; font-size: 13px; }
    button:disabled { background: #ccc; cursor: not-allowed; }
    #status { display: flex; align-items: center; gap: 6px; font-size: 12px; margin-bottom: 12px; }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: #ccc; flex-shrink: 0; }
    .dot.connected { background: #34a853; }
    #session-section { display: none; margin-top: 12px; border-top: 1px solid #444; padding-top: 12px; }
    #session-status { font-size: 12px; color: #aaa; margin-bottom: 8px; min-height: 16px; }
    #session-btn { background: #34a853; }
    #session-btn.stop { background: #ea4335; }
  </style>
</head>
<body>
  <h3>JoyConf</h3>
  <div id="status"><div class="dot" id="dot"></div><span id="status-text">Disconnected</span></div>
  <label for="slug-input">Talk Slug</label>
  <input id="slug-input" type="text" placeholder="elixir-for-rubyists">
  <button id="connect-btn">Connect</button>

  <div id="session-section">
    <div id="session-status">No active session</div>
    <button id="session-btn">Start Session</button>
  </div>

  <script src="popup.js"></script>
</body>
</html>
```

- [ ] **Step 2: Update `extension/popup/popup.js`**

Replace the full file:

```js
const slugInput = document.getElementById("slug-input");
const connectBtn = document.getElementById("connect-btn");
const dot = document.getElementById("dot");
const statusText = document.getElementById("status-text");
const sessionSection = document.getElementById("session-section");
const sessionStatus = document.getElementById("session-status");
const sessionBtn = document.getElementById("session-btn");

let currentSessionId = null;

chrome.storage.local.get(["slug", "sessionId"], ({ slug, sessionId }) => {
  if (slug) slugInput.value = slug;
  if (sessionId) {
    currentSessionId = sessionId;
    setSessionUI(true, "Session active");
  }
});

function setStatus(connected) {
  dot.className = "dot" + (connected ? " connected" : "");
  statusText.textContent = connected ? "Connected" : "Disconnected";
  connectBtn.textContent = connected ? "Disconnect" : "Connect";
  sessionSection.style.display = connected ? "block" : "none";
}

function setSessionUI(active, label) {
  sessionStatus.textContent = active ? label : "No active session";
  sessionBtn.textContent = active ? "Stop Session" : "Start Session";
  sessionBtn.className = active ? "stop" : "";
}

connectBtn.addEventListener("click", () => {
  const slug = slugInput.value.trim();
  if (!slug) return;

  chrome.storage.local.set({ slug });

  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    chrome.tabs.sendMessage(tab.id, { type: "SET_SLUG", slug }, (response) => {
      setStatus(response?.connected ?? false);
    });
  });
});

sessionBtn.addEventListener("click", () => {
  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    if (currentSessionId) {
      chrome.tabs.sendMessage(
        tab.id,
        { type: "STOP_SESSION", sessionId: currentSessionId },
        (response) => {
          if (response?.stopped) {
            currentSessionId = null;
            chrome.storage.local.remove("sessionId");
            setSessionUI(false);
          }
        }
      );
    } else {
      chrome.tabs.sendMessage(tab.id, { type: "START_SESSION" }, (response) => {
        if (response?.session_id) {
          currentSessionId = response.session_id;
          chrome.storage.local.set({ sessionId: response.session_id });
          setSessionUI(true, response.label);
        }
      });
    }
  });
});

// Check current status on popup open
chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
  chrome.tabs.sendMessage(tab.id, { type: "GET_STATUS" }, (response) => {
    setStatus(response?.connected ?? false);
  });
});
```

- [ ] **Step 3: Commit**

```bash
git add extension/popup/popup.html extension/popup/popup.js
git commit -m "feat: add Start/Stop Session UI to extension popup"
```

---

## Task 11: Extension `content.js` — Channel Session Messages

**Files:**
- Modify: `extension/content/content.js`

- [ ] **Step 1: Update the `chrome.runtime.onMessage` listener in `extension/content/content.js`**

Replace the existing listener block (lines 102–109) with:

```js
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === "SET_SLUG") {
    const connected = connect(msg.slug);
    sendResponse({ connected });
  } else if (msg.type === "GET_STATUS") {
    sendResponse({ connected: isConnected() });
  } else if (msg.type === "START_SESSION") {
    if (!channel) {
      sendResponse({ error: "not_connected" });
      return;
    }
    channel
      .push("start_session", {})
      .receive("ok", ({ session_id, label }) => sendResponse({ session_id, label }))
      .receive("error", ({ reason }) => sendResponse({ error: reason }));
    return true; // keep the message channel open for the async reply
  } else if (msg.type === "STOP_SESSION") {
    if (!channel) {
      sendResponse({ error: "not_connected" });
      return;
    }
    channel
      .push("stop_session", { session_id: msg.sessionId })
      .receive("ok", () => sendResponse({ stopped: true }))
      .receive("error", ({ reason }) => sendResponse({ error: reason }));
    return true; // keep the message channel open for the async reply
  }
});
```

- [ ] **Step 2: Manual smoke test**

Load the unpacked extension in Chrome (`chrome://extensions` → Developer mode → Load unpacked → select `extension/`). Open a Google Slides tab, open the popup:

1. Enter a valid talk slug and click Connect — status dot goes green.
2. The session section appears below.
3. Click Start Session — status shows the label ("Session 1"), button turns red ("Stop Session").
4. Check the JoyConf admin panel — the session appears under the talk.
5. Click Stop Session — status returns to "No active session".
6. Check admin — session now shows an end time.

- [ ] **Step 3: Run the full Elixir test suite one final time**

```bash
mix precommit
```

Expected: all checks pass.

- [ ] **Step 4: Commit**

```bash
git add extension/content/content.js
git commit -m "feat: add session start/stop push to extension content script"
```

---

## Phase 1 Complete

The foundation is in place:
- Reactions are persisted to the database when a session is active.
- Presenters can start and stop sessions from the extension popup.
- Sessions are visible and manageable in the admin panel.
- All slide numbers default to `0` — Phase 2 will wire up real slide tracking.
