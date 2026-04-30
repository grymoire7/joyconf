# Phase 2: API Keys + Extension Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate `ReactionChannel` access behind a per-user API key so only authenticated, email-confirmed talk owners can connect the browser extension to their talk.

**Architecture:** A random 64-character hex `api_key` is added to the `users` table and generated on registration. `ReactionChannel.join/3` validates the key (lookup user → check email confirmed → check talk ownership → check participant cap). On API key regeneration, a PubSub broadcast terminates any live channel connections immediately. The Chrome extension stores the key in `chrome.storage.sync` and passes it as a channel param on connect. The Settings LiveView exposes the key with a copy button and a regenerate action. Users with unconfirmed email see a warning banner on the dashboard.

**Tech Stack:** Elixir, Phoenix Channels, Phoenix PubSub, Ecto, Chrome Extension (Manifest V3)

**Repos:** `speechwave` (server) and `chrome-extension` (extension) — both modified in this plan.

---

## File Map

### speechwave repo

#### Modified
| File | Change |
|---|---|
| `lib/speechwave/accounts/user.ex` | Add `api_key` field |
| `lib/speechwave/accounts.ex` | Add `get_user_by_api_key/1`, `regenerate_api_key/1` |
| `lib/speechwave_web/channels/reaction_channel.ex` | Full auth validation + PubSub disconnect subscription |
| `lib/speechwave_web/live/user_live/settings.ex` | Add API key display + regenerate handler |
| `test/speechwave_web/channels/reaction_channel_test.exs` | Add api_key auth tests |
| `test/speechwave/accounts_test.exs` | Add api_key generation + regeneration tests |

#### Created
| File | Purpose |
|---|---|
| `priv/repo/migrations/TIMESTAMP_add_api_key_to_users.exs` | Adds `api_key` column; backfills existing users |

### chrome-extension repo

#### Modified
| File | Change |
|---|---|
| `popup/popup.js` | Store/read `apiKey` from `chrome.storage.sync`; send on channel join; handle new error reasons |
| `content/content.js` | Pass `api_key` in channel params; handle `key_updated` close |

---

## Task 1: Add `api_key` to users

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_api_key_to_users.exs`
- Modify: `lib/speechwave/accounts/user.ex`
- Modify: `lib/speechwave/accounts.ex`
- Modify: `test/speechwave/accounts_test.exs`

- [ ] **Step 1: Write the failing tests**

In `test/speechwave/accounts_test.exs`, add a new describe block at the end of the file:

```elixir
describe "api_key" do
  test "new users are created with a non-nil api_key" do
    user = AccountsFixtures.user_fixture()
    assert is_binary(user.api_key)
    assert String.length(user.api_key) == 64
  end

  test "get_user_by_api_key/1 returns the user for a valid key" do
    user = AccountsFixtures.user_fixture()
    assert Accounts.get_user_by_api_key(user.api_key).id == user.id
  end

  test "get_user_by_api_key/1 returns nil for an unknown key" do
    assert Accounts.get_user_by_api_key("doesnotexist") == nil
  end

  test "regenerate_api_key/1 returns a new api_key different from the old one" do
    user = AccountsFixtures.user_fixture()
    old_key = user.api_key
    {:ok, updated} = Accounts.regenerate_api_key(user)
    assert updated.api_key != old_key
    assert String.length(updated.api_key) == 64
  end

  test "get_user_by_api_key/1 returns nil after key is regenerated" do
    user = AccountsFixtures.user_fixture()
    old_key = user.api_key
    {:ok, _} = Accounts.regenerate_api_key(user)
    assert Accounts.get_user_by_api_key(old_key) == nil
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
mix test test/speechwave/accounts_test.exs --grep "api_key"
```

Expected: `UndefinedFunctionError` for `get_user_by_api_key/1` and `regenerate_api_key/1`, and the `api_key` field missing from user struct.

- [ ] **Step 3: Generate the migration**

```bash
mix ecto.gen.migration add_api_key_to_users
```

Open the generated file and fill it in:

```elixir
defmodule Speechwave.Repo.Migrations.AddApiKeyToUsers do
  use Ecto.Migration
  import Ecto.Query

  def up do
    alter table(:users) do
      add :api_key, :string
    end

    create unique_index(:users, [:api_key])

    # Backfill existing users with a unique api_key
    flush()
    Speechwave.Repo.update_all(
      from(u in "users", where: is_nil(u.api_key)),
      set: [api_key: fragment("lower(hex(randomblob(32)))")]
    )
  end

  def down do
    drop_if_exists unique_index(:users, [:api_key])

    alter table(:users) do
      remove :api_key
    end
  end
end
```

Note: `hex(randomblob(32))` is SQLite-specific — it generates a 64-character hex string, equivalent to what the application generates with `:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)`.

- [ ] **Step 4: Run the migration**

```bash
mix ecto.migrate
```

- [ ] **Step 5: Add `api_key` field to the User schema**

In `lib/speechwave/accounts/user.ex`, inside the `schema "users"` block, add after the `confirmed_at` field:

```elixir
field :api_key, :string
```

- [ ] **Step 6: Add a private changeset for `api_key`**

In `lib/speechwave/accounts/user.ex`, add this private function:

```elixir
defp generate_api_key(changeset) do
  put_change(
    changeset,
    :api_key,
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  )
end
```

- [ ] **Step 7: Call `generate_api_key` in the registration changeset**

In `lib/speechwave/accounts/user.ex`, find the `registration_changeset/3` function. Add `|> generate_api_key()` after `validate_password(opts)`:

```elixir
def registration_changeset(user, attrs, opts \\ []) do
  user
  |> cast(attrs, [:email, :password])
  |> validate_email(opts)
  |> validate_password(opts)
  |> generate_api_key()
end
```

`api_key` must not be in `cast/2` — it is always generated, never accepted from user input.

- [ ] **Step 8: Add `get_user_by_api_key/1` and `regenerate_api_key/1` to Accounts context**

In `lib/speechwave/accounts.ex`, add after the existing `get_user_by_email/1` function:

```elixir
def get_user_by_api_key(api_key) when is_binary(api_key) do
  Repo.get_by(User, api_key: api_key)
end

def regenerate_api_key(%User{} = user) do
  new_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

  user
  |> Ecto.Changeset.change(api_key: new_key)
  |> Repo.update()
end
```

- [ ] **Step 9: Run the tests to confirm they pass**

```bash
mix test test/speechwave/accounts_test.exs
```

Expected: All pass, including the new `api_key` describe block.

- [ ] **Step 10: Commit**

```bash
git add priv/repo/migrations lib/speechwave/accounts/user.ex lib/speechwave/accounts.ex test/speechwave/accounts_test.exs
git commit -m "feat: add api_key to users with generation on registration"
```

---

## Task 2: Add API key auth to ReactionChannel

**Files:**
- Modify: `lib/speechwave_web/channels/reaction_channel.ex`
- Modify: `test/speechwave_web/channels/reaction_channel_test.exs`

The channel now validates: (1) talk exists, (2) api_key matches a user, (3) user email is confirmed, (4) user owns the talk, (5) participant cap not exceeded. On successful join, the channel subscribes to `"user:{id}:disconnect"` for forced disconnects on key regeneration.

- [ ] **Step 1: Update channel tests with auth setup**

Replace the contents of `test/speechwave_web/channels/reaction_channel_test.exs`:

```elixir
defmodule SpeechwaveWeb.ReactionChannelTest do
  use SpeechwaveWeb.ChannelCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  setup do
    user = confirmed_user_fixture()
    talk = talk_fixture(user, %{title: "Test Talk", slug: "test-talk"})
    {:ok, socket} = connect(SpeechwaveWeb.UserSocket, %{})
    {:ok, socket: socket, talk: talk, user: user}
  end

  defp join(socket, slug, api_key) do
    subscribe_and_join(socket, "reactions:#{slug}", %{"api_key" => api_key})
  end

  test "joins when api_key is valid and user owns the talk", %{socket: socket, talk: talk, user: user} do
    assert {:ok, _, _} = join(socket, talk.slug, user.api_key)
  end

  test "rejects join for unknown slug", %{socket: socket, user: user} do
    assert {:error, %{reason: "not_found"}} = join(socket, "nonexistent", user.api_key)
  end

  test "rejects join for invalid api_key", %{socket: socket, talk: talk} do
    assert {:error, %{reason: "unauthorized"}} = join(socket, talk.slug, "badkey")
  end

  test "rejects join when user email is not confirmed", %{socket: socket} do
    unconfirmed = user_fixture()
    talk = talk_fixture(unconfirmed, %{slug: "unconfirmed-talk"})
    assert {:error, %{reason: "email_not_confirmed"}} = join(socket, talk.slug, unconfirmed.api_key)
  end

  test "rejects join when api_key belongs to a user who does not own the talk", %{socket: socket, talk: talk} do
    other_user = confirmed_user_fixture()
    assert {:error, %{reason: "unauthorized"}} = join(socket, talk.slug, other_user.api_key)
  end

  test "pushes new_reaction to client when Endpoint broadcasts", %{socket: socket, talk: talk, user: user} do
    {:ok, _, _} = join(socket, talk.slug, user.api_key)
    SpeechwaveWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "❤️"})
    assert_push "new_reaction", %{emoji: "❤️"}
  end

  describe "session management via channel" do
    setup %{socket: socket, talk: talk, user: user} do
      {:ok, _, joined} = join(socket, talk.slug, user.api_key)
      %{joined: joined, talk: talk, user: user}
    end

    test "start_session creates a session and replies with session_id and label", %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id, label: "Session 1"}
      assert Speechwave.Talks.get_session(session_id) != nil
    end

    test "start_session is idempotent when a session is already active", %{joined: joined} do
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
      assert Speechwave.Talks.get_session(session_id).ended_at != nil
    end

    test "stop_session returns error for unknown session_id", %{joined: joined} do
      ref = push(joined, "stop_session", %{"session_id" => 999_999})
      assert_reply ref, :error, %{reason: "not_found"}
    end

    test "stop_session returns error for a session belonging to a different talk",
         %{joined: joined, user: user} do
      other_talk = talk_fixture(user, %{slug: "other-#{System.unique_integer()}"})
      {:ok, other_session} = Speechwave.Talks.start_session(other_talk)
      ref = push(joined, "stop_session", %{"session_id" => other_session.id})
      assert_reply ref, :error, %{reason: "unauthorized"}
    end

    test "rejects start_session when monthly full-session limit is reached",
         %{joined: joined, talk: talk} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      full_end = DateTime.add(now, 15 * 60, :second)

      for i <- 1..10 do
        Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
          talk_id: talk.id,
          label: "Seed #{i}",
          started_at: now,
          ended_at: full_end
        })
      end

      ref = push(joined, "start_session", %{})
      assert_reply ref, :error, %{reason: "session_limit_reached"}
    end
  end

  describe "slide_changed" do
    setup %{socket: socket, talk: talk, user: user} do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "slides:#{talk.slug}")
      {:ok, _, joined} = join(socket, talk.slug, user.api_key)
      %{joined: joined, talk: talk}
    end

    test "broadcasts slide number to slides PubSub topic", %{joined: joined} do
      ref = push(joined, "slide_changed", %{"slide" => 5})
      assert_reply ref, :ok
      assert_receive %Phoenix.Socket.Broadcast{event: "slide_changed", payload: %{slide: 5}}, 500
    end

    test "does not broadcast for slide 0", %{joined: joined} do
      ref = push(joined, "slide_changed", %{"slide" => 0})
      assert_reply ref, :ok
      refute_receive %Phoenix.Socket.Broadcast{event: "slide_changed"}, 200
    end
  end
end
```

The tests use `confirmed_user_fixture/0` — you will add that helper in the next step.

- [ ] **Step 2: Add `confirmed_user_fixture/0` to `AccountsFixtures`**

Open `test/support/fixtures/accounts_fixtures.ex`. Add after the existing `user_fixture/1`:

```elixir
def confirmed_user_fixture(attrs \\ %{}) do
  user = user_fixture(attrs)
  now = DateTime.utc_now(:second)
  Speechwave.Repo.update!(Ecto.Changeset.change(user, confirmed_at: now))
end
```

- [ ] **Step 3: Run tests to confirm they fail for the right reason**

```bash
mix test test/speechwave_web/channels/reaction_channel_test.exs
```

Expected: Most tests fail because the channel still uses the old join signature (no `api_key` in params). The compile step may also produce warnings about unreachable clauses. These will all be fixed in the next step.

- [ ] **Step 4: Replace `lib/speechwave_web/channels/reaction_channel.ex`**

```elixir
defmodule SpeechwaveWeb.ReactionChannel do
  use Phoenix.Channel

  alias Speechwave.Accounts
  alias Speechwave.Plans
  alias Speechwave.Talks
  alias SpeechwaveWeb.Presence

  def join("reactions:" <> slug, %{"api_key" => api_key}, socket) do
    with {:talk, %Talks.Talk{} = talk} <- {:talk, Talks.get_talk_by_slug(slug)},
         {:user, %Accounts.User{} = user} <- {:user, Accounts.get_user_by_api_key(api_key)},
         {:confirmed, true} <- {:confirmed, not is_nil(user.confirmed_at)},
         {:owner, true} <- {:owner, talk.user_id == user.id},
         {:capacity, :ok} <-
           {:capacity,
            Plans.check(:max_participants, user.plan, Presence.list("reactions:#{slug}") |> map_size())} do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "user:#{user.id}:disconnect")
      send(self(), :after_join)
      {:ok, assign(socket, talk: talk, user: user)}
    else
      {:talk, nil} -> {:error, %{reason: "not_found"}}
      {:user, nil} -> {:error, %{reason: "unauthorized"}}
      {:confirmed, false} -> {:error, %{reason: "email_not_confirmed"}}
      {:owner, false} -> {:error, %{reason: "unauthorized"}}
      {:capacity, {:error, :limit_reached}} -> {:error, %{reason: "capacity_reached"}}
    end
  end

  def join("reactions:" <> _slug, _params, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, "anon:#{inspect(self())}", %{
        joined_at: System.system_time(:second)
      })

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "disconnect"}, socket) do
    {:stop, :normal, socket}
  end

  def handle_in("start_session", _payload, socket) do
    talk = socket.assigns.talk
    user = socket.assigns.user
    scope = %Speechwave.Accounts.Scope{user: user}
    full_count = Talks.count_full_sessions_this_month(scope)

    case Plans.check(:full_sessions_per_month, user.plan, full_count) do
      :ok ->
        case Talks.start_session(talk) do
          {:ok, session} ->
            {:reply, {:ok, %{session_id: session.id, label: session.label}}, socket}

          {:error, _changeset} ->
            {:reply, {:error, %{reason: "failed"}}, socket}
        end

      {:error, :limit_reached} ->
        {:reply, {:error, %{reason: "session_limit_reached"}}, socket}
    end
  end

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

  def handle_in("slide_changed", %{"slide" => slide}, socket)
      when is_integer(slide) and slide > 0 do
    SpeechwaveWeb.Endpoint.broadcast!(
      "slides:#{socket.assigns.talk.slug}",
      "slide_changed",
      %{slide: slide}
    )

    {:reply, :ok, socket}
  end

  def handle_in("slide_changed", _payload, socket) do
    {:reply, :ok, socket}
  end
end
```

Note: The `get_talk_with_owner/1` call is replaced — we now look up the talk and user separately using the api_key, which is cleaner and avoids the preload.

- [ ] **Step 5: Run channel tests to confirm they pass**

```bash
mix test test/speechwave_web/channels/reaction_channel_test.exs
```

Expected: All pass.

- [ ] **Step 6: Run the full test suite**

```bash
mix test
```

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave_web/channels/reaction_channel.ex \
        test/speechwave_web/channels/reaction_channel_test.exs \
        test/support/fixtures/accounts_fixtures.ex
git commit -m "feat: add API key auth to ReactionChannel with email confirmation gate"
```

---

## Task 3: Add API key display and regenerate to Settings

**Files:**
- Modify: `lib/speechwave_web/live/user_live/settings.ex`

- [ ] **Step 1: Write failing tests for the settings page**

In `test/speechwave_web/live/user_live/settings_live_test.exs` (the generated test file), add a new describe block at the end:

```elixir
describe "API key section" do
  test "shows the user's api_key in a read-only field", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")
    assert has_element?(view, "#api-key-display")
    assert render(view) =~ user.api_key
  end

  test "regenerate button generates a new api_key", %{conn: conn, user: user} do
    old_key = user.api_key
    {:ok, view, _html} = live(conn, ~p"/users/settings")
    view |> element("#regenerate-api-key-btn") |> render_click()
    refute render(view) =~ old_key
    updated_user = Speechwave.Accounts.get_user!(user.id)
    assert updated_user.api_key != old_key
  end

  test "regenerate broadcasts disconnect to active channel connections", %{conn: conn, user: user} do
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "user:#{user.id}:disconnect")
    {:ok, view, _html} = live(conn, ~p"/users/settings")
    view |> element("#regenerate-api-key-btn") |> render_click()
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 500
  end
end
```

You will need to add `get_user!/1` to the Accounts context if it doesn't exist. Check `lib/speechwave/accounts.ex` — it likely already has it (generated by `phx.gen.auth`).

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
mix test test/speechwave_web/live/user_live/settings_live_test.exs --grep "API key"
```

Expected: Tests fail — `#api-key-display` and `#regenerate-api-key-btn` elements don't exist yet.

- [ ] **Step 3: Add the API key assign and regenerate handler to `UserLive.Settings`**

In `lib/speechwave_web/live/user_live/settings.ex`, update the `mount/3` function (the one without a token) to add the api_key assign:

```elixir
def mount(_params, _session, socket) do
  user = socket.assigns.current_scope.user
  email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
  password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

  socket =
    socket
    |> assign(:current_email, user.email)
    |> assign(:email_form, to_form(email_changeset))
    |> assign(:password_form, to_form(password_changeset))
    |> assign(:trigger_submit, false)
    |> assign(:api_key, user.api_key)

  {:ok, socket}
end
```

Add the regenerate event handler at the end of the module (before the closing `end`):

```elixir
def handle_event("regenerate_api_key", _params, socket) do
  user = socket.assigns.current_scope.user
  {:ok, updated_user} = Accounts.regenerate_api_key(user)
  Phoenix.PubSub.broadcast(Speechwave.PubSub, "user:#{user.id}:disconnect", %Phoenix.Socket.Broadcast{
    topic: "user:#{user.id}:disconnect",
    event: "disconnect",
    payload: %{}
  })
  {:noreply, assign(socket, :api_key, updated_user.api_key)}
end
```

- [ ] **Step 4: Add the API key section to the Settings template**

In `lib/speechwave_web/live/user_live/settings.ex`, inside the `render/1` function, add the API key section after the password form (before the closing `</Layouts.app>`):

```heex
<div class="divider" />

<div class="space-y-2">
  <h3 class="font-semibold text-base-content">Browser Extension API Key</h3>
  <p class="text-sm text-base-content/70">
    Paste this key into the Speechwave browser extension to authenticate.
    Keep it secret.
  </p>
  <div class="flex gap-2 items-center">
    <input
      id="api-key-display"
      type="text"
      readonly
      value={@api_key}
      class="flex-1 font-mono text-sm px-3 py-2 rounded-lg border border-base-300 bg-base-200 text-base-content"
      onclick="this.select()"
    />
    <button
      id="regenerate-api-key-btn"
      phx-click="regenerate_api_key"
      data-confirm="Regenerate your API key? Any active extension connections will be disconnected immediately."
      class="px-4 py-2 text-sm font-medium rounded-lg border border-base-300 hover:bg-base-200 transition-colors"
    >
      Regenerate
    </button>
  </div>
</div>
```

- [ ] **Step 5: Run tests**

```bash
mix test test/speechwave_web/live/user_live/settings_live_test.exs
```

Expected: All pass, including the new API key tests.

- [ ] **Step 6: Run the full test suite**

```bash
mix test
```

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave_web/live/user_live/settings.ex \
        test/speechwave_web/live/user_live/settings_live_test.exs
git commit -m "feat: add API key display and regenerate to user settings"
```

---

## Task 4: Add confirmation banner to Dashboard

**Files:**
- Modify: `lib/speechwave_web/live/dashboard_live.ex`
- Modify: `lib/speechwave_web/live/dashboard_live.html.heex`
- Modify: `test/speechwave_web/live/dashboard_live_test.exs`

- [ ] **Step 1: Write failing tests**

In `test/speechwave_web/live/dashboard_live_test.exs`, add a new describe block at the end:

```elixir
describe "email confirmation banner" do
  test "shows banner for unconfirmed users", %{conn: _conn} do
    unconfirmed = AccountsFixtures.user_fixture()
    conn = log_in_user(build_conn(), unconfirmed)
    {:ok, view, _html} = live(conn, "/dashboard")
    assert has_element?(view, "#email-confirmation-banner")
  end

  test "does not show banner for confirmed users", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")
    refute has_element?(view, "#email-confirmation-banner")
  end
end
```

The existing `setup` uses a confirmed user (via `confirmed_user_fixture` — update it if needed, see note below).

> **Note:** The dashboard test `setup` currently creates a user with `user_fixture()`. Change it to `confirmed_user_fixture()` so the banner tests have a clean baseline. Update the `setup` block:
> ```elixir
> setup %{conn: conn} do
>   user = AccountsFixtures.confirmed_user_fixture()
>   %{conn: log_in_user(conn, user), user: user}
> end
> ```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
mix test test/speechwave_web/live/dashboard_live_test.exs --grep "confirmation banner"
```

Expected: Tests fail — `#email-confirmation-banner` doesn't exist.

- [ ] **Step 3: Add `confirmed?` assign to `DashboardLive.mount/3`**

In `lib/speechwave_web/live/dashboard_live.ex`, add `:confirmed?` to the assign list in `mount/3`:

```elixir
def mount(_params, _session, socket) do
  scope = socket.assigns.current_scope

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
     confirmed?: not is_nil(scope.user.confirmed_at)
   )}
end
```

- [ ] **Step 4: Add the banner to `dashboard_live.html.heex`**

At the very top of the template body (inside `<Layouts.app ...>` but before any other content), add:

```heex
<%= if not @confirmed? do %>
  <div id="email-confirmation-banner" class="mb-4 px-4 py-3 bg-amber-50 border border-amber-300 rounded-lg text-sm text-amber-800 flex items-center justify-between">
    <span>
      Please confirm your email address to activate the browser extension.
    </span>
    <.link href={~p"/users/settings"} class="underline font-medium ml-4 shrink-0">
      Resend confirmation
    </.link>
  </div>
<% end %>
```

- [ ] **Step 5: Run tests**

```bash
mix test test/speechwave_web/live/dashboard_live_test.exs
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave_web/live/dashboard_live.ex \
        lib/speechwave_web/live/dashboard_live.html.heex \
        test/speechwave_web/live/dashboard_live_test.exs
git commit -m "feat: add email confirmation banner to dashboard"
```

---

## Task 5: Update the Chrome extension

**Repo:** `/Users/tracy/projects/speechwave-live/chrome-extension`

**Files:**
- Modify: `popup/popup.js`
- Modify: `content/content.js`

All steps in this task are performed in the `chrome-extension` repo.

- [ ] **Step 1: Update `popup/popup.js` to handle API key setup and pass it on connect**

The popup needs to:
1. Check for a stored `apiKey` on open; if missing, show a setup screen
2. Save the key to `chrome.storage.sync` once entered
3. Pass the key when sending `SET_SLUG` to the content script

Replace the contents of `popup/popup.js`:

```javascript
const DEV_MODE = false; // set to true locally for testing

// --- DOM references ---
const setupSection = document.getElementById("setup-section");
const mainSection = document.getElementById("main-section");
const apiKeyInput = document.getElementById("api-key-input");
const saveApiKeyBtn = document.getElementById("save-api-key-btn");

const slugInput = document.getElementById("slug-input");
const connectBtn = document.getElementById("connect-btn");
const dot = document.getElementById("dot");
const statusText = document.getElementById("status-text");
const sessionSection = document.getElementById("session-section");
const sessionStatus = document.getElementById("session-status");
const sessionBtn = document.getElementById("session-btn");
const slideIndicator = document.getElementById("slide-indicator");
const fireworksToggle = document.getElementById("fireworks-toggle");
const testFireworksBtn = document.getElementById("test-fireworks-btn");
const errorMsg = document.getElementById("error-msg");

let currentSessionId = null;
let storedApiKey = null;

function setError(msg) {
  if (msg) {
    errorMsg.textContent = msg;
    errorMsg.style.display = "block";
  } else {
    errorMsg.textContent = "";
    errorMsg.style.display = "none";
  }
}

function showSetup() {
  setupSection.style.display = "block";
  mainSection.style.display = "none";
}

function showMain() {
  setupSection.style.display = "none";
  mainSection.style.display = "block";
}

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

function setSlideIndicator(slide) {
  slideIndicator.textContent = slide > 0 ? `Slide ${slide}` : "Slide —";
}

// --- API key setup ---
saveApiKeyBtn.addEventListener("click", () => {
  const key = apiKeyInput.value.trim();
  if (!key) return;
  chrome.storage.sync.set({ apiKey: key }, () => {
    storedApiKey = key;
    showMain();
    setError(null);
  });
});

// --- Fireworks ---
chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled }) => {
  fireworksToggle.checked = fireworksEnabled;
});

fireworksToggle.addEventListener("change", () => {
  const enabled = fireworksToggle.checked;
  chrome.storage.sync.set({ fireworksEnabled: enabled });
  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    chrome.tabs.sendMessage(tab.id, { type: "SET_FIREWORKS", enabled }, () => {
      void chrome.runtime.lastError;
    });
  });
});

if (DEV_MODE) {
  testFireworksBtn.style.display = "block";
  testFireworksBtn.addEventListener("click", () => {
    chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
      chrome.tabs.sendMessage(tab.id, { type: "TEST_FIREWORKS" }, () => {
        void chrome.runtime.lastError;
      });
    });
  });
}

// --- Connect ---
connectBtn.addEventListener("click", () => {
  const slug = slugInput.value.trim();
  if (!slug) return;
  setError(null);
  chrome.storage.local.set({ slug });
  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    chrome.tabs.sendMessage(tab.id, { type: "SET_SLUG", slug, apiKey: storedApiKey }, (response) => {
      setStatus(response?.connected ?? false);
    });
  });
});

// --- Session ---
sessionBtn.addEventListener("click", () => {
  setError(null);
  chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
    if (currentSessionId) {
      chrome.tabs.sendMessage(tab.id, { type: "STOP_SESSION", sessionId: currentSessionId }, (response) => {
        if (response?.stopped) {
          currentSessionId = null;
          chrome.storage.local.remove("sessionId");
          setSessionUI(false);
        }
      });
    } else {
      chrome.tabs.sendMessage(tab.id, { type: "START_SESSION" }, (response) => {
        if (response?.session_id) {
          currentSessionId = response.session_id;
          chrome.storage.local.set({ sessionId: response.session_id });
          setSessionUI(true, response.label);
        } else if (response?.error) {
          const messages = {
            session_limit_reached: "Monthly session limit reached",
            not_connected: "Not connected to a talk",
          };
          setError(messages[response.error] || "Could not start session");
        }
      });
    }
  });
});

// --- Init ---
chrome.storage.sync.get(["apiKey"], ({ apiKey }) => {
  if (apiKey) {
    storedApiKey = apiKey;
    showMain();

    chrome.storage.local.get(["slug", "sessionId"], ({ slug, sessionId }) => {
      if (slug) slugInput.value = slug;
      if (sessionId) {
        currentSessionId = sessionId;
        setSessionUI(true, "Session active");
      }
    });

    chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
      chrome.tabs.sendMessage(tab.id, { type: "GET_STATUS" }, (response) => {
        setStatus(response?.connected ?? false);
        setSlideIndicator(response?.slide ?? 0);
      });
    });
  } else {
    showSetup();
  }
});

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === "SLIDE_CHANGED") {
    setSlideIndicator(msg.slide);
  } else if (msg.type === "CONNECT_ERROR") {
    const messages = {
      capacity_reached: "Talk is at capacity",
      unauthorized: "Invalid API key or you don't own this talk",
      email_not_confirmed: "Please confirm your email before using the extension",
      not_found: "Talk not found",
      key_updated: "Your API key was regenerated. Please update it in the extension.",
    };
    setError(messages[msg.reason] || "Connection failed");
    setStatus(false);
  }
});
```

- [ ] **Step 2: Add the setup section HTML to `popup/popup.html`**

Open `popup/popup.html`. Add the setup section div before the main section. The exact structure depends on the existing HTML, but add these elements:

```html
<!-- API key setup screen — shown when no key is stored -->
<div id="setup-section" style="display:none">
  <p class="setup-msg">Paste your Speechwave API key to get started.<br>
    Find it in <a href="https://speechwave.fly.dev/users/settings" target="_blank">Account Settings</a>.
  </p>
  <input id="api-key-input" type="text" placeholder="Your API key" class="api-key-input" />
  <button id="save-api-key-btn" class="primary">Save Key</button>
</div>

<!-- Main UI — shown once api key is saved -->
<div id="main-section" style="display:none">
  <!-- existing popup content goes here -->
</div>
```

Wrap the existing popup content (slug input, connect button, session section, etc.) inside `<div id="main-section">`.

- [ ] **Step 3: Update `content/content.js` to pass `api_key` in channel params**

In `content/content.js`, find the `connect(slug)` function signature and update it to accept `apiKey`:

```javascript
// Before:
function connect(slug) {

// After:
function connect(slug, apiKey) {
```

Inside `connect`, find the channel join line:

```javascript
// Before:
channel = socket.channel(`reactions:${slug}`, {});

// After:
channel = socket.channel(`reactions:${slug}`, { api_key: apiKey });
```

Update the `SET_SLUG` message handler to pass the apiKey:

```javascript
// Before:
if (msg.type === "SET_SLUG") {
  const connected = connect(msg.slug);
  sendResponse({ connected });
}

// After:
if (msg.type === "SET_SLUG") {
  const connected = connect(msg.slug, msg.apiKey);
  sendResponse({ connected });
}
```

Update the auto-connect on page load to also read `apiKey`:

```javascript
// Before:
chrome.storage.local.get("slug", ({ slug }) => {
  if (slug) connect(slug);
});

// After:
chrome.storage.local.get("slug", ({ slug }) => {
  if (slug) {
    chrome.storage.sync.get("apiKey", ({ apiKey }) => {
      if (apiKey) connect(slug, apiKey);
    });
  }
});
```

Handle the `key_updated` close reason in the channel error handler (inside `connect()`):

```javascript
// In the channel.join() .receive("error") callback, update the error message forwarding:
.receive("error", ({ reason }) => {
  console.error(`[Speechwave] Channel join failed: ${reason}`);
  stopSlideObserver();
  socket.disconnect();
  socket = null;
  channel = null;
  chrome.runtime.sendMessage({ type: "CONNECT_ERROR", reason }, () => {
    void chrome.runtime.lastError;
  });
});
```

Also add a handler for when the server closes the channel (key regenerated):

```javascript
channel.onClose(() => {
  stopSlideObserver();
  socket = null;
  channel = null;
  chrome.runtime.sendMessage({ type: "CONNECT_ERROR", reason: "key_updated" }, () => {
    void chrome.runtime.lastError;
  });
});
```

- [ ] **Step 4: Test the extension manually**

Load the extension in Chrome (`chrome://extensions` → Developer mode → Load unpacked → select the `chrome-extension` directory).

1. Open the popup. Confirm the setup screen appears (no API key stored yet).
2. Enter your API key from the Settings page. Confirm the main UI appears.
3. Open a Google Slides presentation. Enter your talk slug and connect.
4. Confirm the channel joins successfully.
5. From another browser, try joining the same channel without a key — confirm it fails.

- [ ] **Step 5: Commit the extension changes**

In the `chrome-extension` repo:

```bash
git add popup/popup.js popup/popup.html content/content.js
git commit -m "feat: add API key setup and auth to extension popup and channel join"
```

---

## Task 6: Run precommit in speechwave repo and verify

- [ ] **Step 1: Run precommit**

```bash
mix precommit
```

Fix any formatting issues and commit:

```bash
git add -A && git commit -m "chore: precommit fixes"
```

Skip this commit if nothing changed.

- [ ] **Step 2: Run the full test suite**

```bash
mix test
```

Expected: All pass, zero failures.
