# Passwordless Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace phx.gen.auth password-based login with magic links + OAuth SSO (Google, Microsoft, GitHub), removing all password/bcrypt infrastructure.

**Architecture:** Keep the existing session and magic link token infrastructure intact — it already works. Remove password code, add a direct magic link controller action (bypassing the Confirmation LiveView), add Assent OAuth with a `UserIdentity` table for provider associations, and add a dev login backdoor.

**Tech Stack:** Elixir/Phoenix 1.8, LiveView, Ecto/SQLite, Swoosh email, `assent ~> 0.2` for OAuth.

---

## Existing Infrastructure to Keep

Before making changes, understand what already works:
- `Speechwave.Accounts.UserToken.build_email_token/2` — generates hashed tokens for any context
- `UserToken.verify_magic_link_token_query/1` — verifies tokens with context `"login"`, 15-min TTL
- `Accounts.deliver_login_instructions/2` — sends magic link email (currently only if user exists)
- `Accounts.login_user_by_magic_link/1` — verifies token and logs user in
- `SpeechwaveWeb.UserAuth` — session plug, `log_in_user/3`, `disconnect_sessions/1`
- `UserToken.build_session_token/1` + `verify_session_token_query/1` — session tokens unchanged

## File Map

**Modified:**
- `mix.exs` — remove `bcrypt_elixir`, add `assent`
- `lib/speechwave/accounts/user.ex` — remove password/bcrypt fields and functions
- `lib/speechwave/accounts.ex` — remove password functions, simplify `login_user_by_magic_link`, add `register_or_get_user_by_email/1`, add OAuth functions
- `lib/speechwave/accounts/user_notifier.ex` — simplify to single magic link email template
- `lib/speechwave_web/controllers/user_session_controller.ex` — add `magic_link/2` and OAuth actions, remove `update_password/2`
- `lib/speechwave_web/router.ex` — remove old routes, add new routes
- `lib/speechwave_web/live/user_live/login.ex` — remove password form, add OAuth buttons
- `lib/speechwave_web/live/user_live/settings.ex` — remove password section, add connected accounts
- `config/runtime.exs` — add Assent provider config
- `priv/repo/seeds.exs` — remove password from admin seed
- `test/support/fixtures/accounts_fixtures.ex` — remove password helpers, add OAuth fixture
- `test/speechwave/accounts_test.exs` — remove password tests, add OAuth tests
- `test/speechwave_web/controllers/user_session_controller_test.exs` — update for new actions
- `test/speechwave_web/live/user_live/login_test.exs` — update for new UI
- `test/speechwave_web/live/user_live/settings_test.exs` — update for removed password section

**Created:**
- `lib/speechwave/accounts/user_identity.ex` — OAuth identity schema
- `lib/speechwave_web/controllers/dev_login_controller.ex` — dev-only login backdoor
- `priv/repo/migrations/TIMESTAMP_drop_password_columns.exs`
- `priv/repo/migrations/TIMESTAMP_create_user_identities.exs`

**Deleted:**
- `lib/speechwave_web/live/user_live/registration.ex`
- `lib/speechwave_web/live/user_live/confirmation.ex`
- `test/speechwave_web/live/user_live/registration_test.exs`
- `test/speechwave_web/live/user_live/confirmation_test.exs`

---

## Task 1: Swap Dependencies

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Update deps in mix.exs**

In `mix.exs`, remove `{:bcrypt_elixir, "~> 3.0"}` and add `{:assent, "~> 0.2"}`:

```elixir
# Remove this line:
{:bcrypt_elixir, "~> 3.0"},
# Add this line:
{:assent, "~> 0.2"},
```

- [ ] **Step 2: Fetch deps**

```bash
mix deps.get
```

Expected: assent fetched, bcrypt_elixir removed.

- [ ] **Step 3: Compile to check for bcrypt references**

```bash
mix compile 2>&1 | grep -i bcrypt
```

Expected: compilation may warn about unused bcrypt calls (not yet removed). That's OK — we'll clean up in the next task.

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "chore: replace bcrypt_elixir with assent"
```

---

## Task 2: Clean User Schema

Remove all password and bcrypt code from `User`. **This must happen before the DB migration** — if the schema still declares `hashed_password`, Ecto will try to SELECT it and fail after the column is dropped.

**Files:**
- Modify: `lib/speechwave/accounts/user.ex`

- [ ] **Step 1: Replace the entire User schema**

The new `lib/speechwave/accounts/user.ex`:

```elixir
defmodule Speechwave.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :authenticated_at, :utc_datetime, virtual: true
    field :api_key, :string
    field :plan, Ecto.Enum, values: [:free, :pro, :org], default: :free
    field :is_admin, :boolean, default: false

    has_many :identities, Speechwave.Accounts.UserIdentity

    timestamps(type: :utc_datetime)
  end

  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> maybe_generate_api_key()
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &String.downcase/1)
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Speechwave.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp maybe_generate_api_key(changeset) do
    if get_field(changeset, :api_key) do
      changeset
    else
      generate_api_key(changeset)
    end
  end

  defp generate_api_key(changeset) do
    put_change(
      changeset,
      :api_key,
      :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    )
  end

  @doc "Used exclusively for plan changes."
  def plan_changeset(user, attrs) do
    user
    |> cast(attrs, [:plan])
    |> validate_required([:plan])
    |> validate_inclusion(:plan, [:free, :pro, :org])
  end
end
```

- [ ] **Step 2: Compile to verify no password references remain**

```bash
mix compile 2>&1 | grep -E "bcrypt|hashed_password|confirmed_at"
```

Expected: no output (any remaining references are in Accounts context, which we'll clean next).

- [ ] **Step 3: Commit**

```bash
git add lib/speechwave/accounts/user.ex
git commit -m "refactor: remove password and confirmed_at from User schema"
```

---

## Task 3: Clean Accounts Context

Remove password functions, simplify `login_user_by_magic_link`, add `register_or_get_user_by_email/1`.

**Files:**
- Modify: `lib/speechwave/accounts.ex`

- [ ] **Step 1: Remove password functions from Accounts**

Delete the following functions from `lib/speechwave/accounts.ex`:
- `get_user_by_email_and_password/2`
- `change_user_password/3`
- `update_user_password/2`

- [ ] **Step 2: Simplify login_user_by_magic_link**

Replace the existing `login_user_by_magic_link/1` with this simplified version that removes all confirmed_at/hashed_password cases:

```elixir
@doc """
Logs the user in by magic link token. The token is single-use and deleted on success.
"""
def login_user_by_magic_link(token) do
  {:ok, query} = UserToken.verify_magic_link_token_query(token)

  case Repo.one(query) do
    {user, token_record} ->
      Repo.delete!(token_record)
      {:ok, {user, []}}

    nil ->
      {:error, :not_found}
  end
end
```

- [ ] **Step 3: Add register_or_get_user_by_email/1**

Add after `register_user/1`:

```elixir
@doc """
Returns an existing user by email, or registers a new one.
Used by the magic link flow so that submitting an email always succeeds.
"""
def register_or_get_user_by_email(email) when is_binary(email) do
  case get_user_by_email(email) do
    nil -> register_user(%{email: email})
    user -> {:ok, user}
  end
end
```

- [ ] **Step 4: Update deliver_login_instructions to use the new magic link URL**

The function signature stays the same — callers will pass the new URL. No changes needed here; the URL change happens in the Login LiveView in Task 10.

- [ ] **Step 5: Remove update_user_and_delete_all_tokens/1 if only used by password functions**

Check if `update_user_and_delete_all_tokens/1` is still needed:

```bash
grep -n "update_user_and_delete_all_tokens" lib/speechwave/accounts.ex
```

It's now only called by `update_user_email/2` (for email change). Keep it.

- [ ] **Step 6: Compile**

```bash
mix compile 2>&1 | grep error
```

Expected: no errors. If there are errors from tests referencing deleted functions, we'll fix tests in Task 15.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/accounts.ex
git commit -m "refactor: remove password functions from Accounts context"
```

---

## Task 4: Migration — Drop Password Columns

Now that the schema no longer references `hashed_password` or `confirmed_at`, we can safely drop them.

**Files:**
- Create: migration file

- [ ] **Step 1: Generate migration**

```bash
mix ecto.gen.migration drop_password_columns_from_users
```

- [ ] **Step 2: Write the migration**

Open the generated file at `priv/repo/migrations/TIMESTAMP_drop_password_columns_from_users.exs`:

```elixir
defmodule Speechwave.Repo.Migrations.DropPasswordColumnsFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :hashed_password
      remove :confirmed_at
    end
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: migration runs without error.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: drop hashed_password and confirmed_at columns from users"
```

---

## Task 5: UserIdentity Schema + Migration

**Files:**
- Create: `lib/speechwave/accounts/user_identity.ex`
- Create: migration file
- Test: `test/speechwave/accounts_test.exs` (new describe block)

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave/accounts_test.exs` (at the end, before the last `end`):

```elixir
describe "user_identities" do
  test "find_or_create_user_from_oauth creates user and identity when neither exists" do
    assert {:ok, user} =
             Accounts.find_or_create_user_from_oauth("google", %{
               "sub" => "google-uid-123",
               "email" => "newuser@example.com",
               "email_verified" => true
             })

    assert user.email == "newuser@example.com"
    assert Repo.get_by(Speechwave.Accounts.UserIdentity, provider: "google", uid: "google-uid-123")
  end

  test "find_or_create_user_from_oauth links identity to existing user with matching email" do
    existing = user_fixture()

    assert {:ok, user} =
             Accounts.find_or_create_user_from_oauth("google", %{
               "sub" => "google-uid-456",
               "email" => existing.email,
               "email_verified" => true
             })

    assert user.id == existing.id
  end

  test "find_or_create_user_from_oauth returns existing user+identity on repeat login" do
    {:ok, user} =
      Accounts.find_or_create_user_from_oauth("github", %{
        "sub" => "gh-uid-789",
        "email" => "repeat@example.com",
        "email_verified" => true
      })

    assert {:ok, same_user} =
             Accounts.find_or_create_user_from_oauth("github", %{
               "sub" => "gh-uid-789",
               "email" => "repeat@example.com",
               "email_verified" => true
             })

    assert same_user.id == user.id
    assert Repo.aggregate(Speechwave.Accounts.UserIdentity, :count) == 1
  end

  test "find_or_create_user_from_oauth returns error when email is not verified" do
    assert {:error, :email_not_verified} =
             Accounts.find_or_create_user_from_oauth("google", %{
               "sub" => "uid-unverified",
               "email" => "unverified@example.com",
               "email_verified" => false
             })
  end

  test "list_user_identities returns all identities for user" do
    user = user_fixture()
    {:ok, _} = Accounts.find_or_create_user_from_oauth("google", %{"sub" => "g1", "email" => user.email, "email_verified" => true})
    {:ok, _} = Accounts.find_or_create_user_from_oauth("github", %{"sub" => "gh1", "email" => user.email, "email_verified" => true})

    identities = Accounts.list_user_identities(user)
    assert length(identities) == 2
    assert Enum.map(identities, & &1.provider) |> Enum.sort() == ["github", "google"]
  end

  test "delete_user_identity removes the identity" do
    user = user_fixture()
    {:ok, _} = Accounts.find_or_create_user_from_oauth("google", %{"sub" => "g2", "email" => user.email, "email_verified" => true})
    [identity] = Accounts.list_user_identities(user)

    assert {:ok, _} = Accounts.delete_user_identity(identity)
    assert Accounts.list_user_identities(user) == []
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/speechwave/accounts_test.exs --failed 2>&1 | tail -20
```

Expected: compile error — `Accounts.find_or_create_user_from_oauth` does not exist.

- [ ] **Step 3: Generate the migration**

```bash
mix ecto.gen.migration create_user_identities
```

- [ ] **Step 4: Write the migration**

```elixir
defmodule Speechwave.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :uid, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_identities, [:user_id])
    create unique_index(:user_identities, [:provider, :uid])
  end
end
```

- [ ] **Step 5: Run the migration**

```bash
mix ecto.migrate
```

- [ ] **Step 6: Create UserIdentity schema**

Create `lib/speechwave/accounts/user_identity.ex`:

```elixir
defmodule Speechwave.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :uid, :string
    belongs_to :user, Speechwave.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :uid, :user_id])
    |> validate_required([:provider, :uid, :user_id])
    |> unique_constraint([:provider, :uid])
  end
end
```

- [ ] **Step 7: Add OAuth functions to Accounts context**

Add to `lib/speechwave/accounts.ex`:

First, add `UserIdentity` to the alias at the top:

```elixir
alias Speechwave.Accounts.{User, UserIdentity, UserNotifier, UserToken}
```

Then add these functions (after `register_or_get_user_by_email/1`):

```elixir
@doc """
Finds or creates a user from an OAuth provider callback.

Looks up an existing identity by {provider, uid}. If found, returns the
associated user. If not found, upserts a user by email and creates the
identity record. Returns {:error, :email_not_verified} if the provider
did not verify the email.
"""
def find_or_create_user_from_oauth(provider, %{"sub" => uid, "email" => email} = user_info) do
  if user_info["email_verified"] == false do
    {:error, :email_not_verified}
  else
    Repo.transact(fn ->
      case Repo.get_by(UserIdentity, provider: provider, uid: uid) do
        %UserIdentity{} = identity ->
          {:ok, Repo.preload(identity, :user).user}

        nil ->
          with {:ok, user} <- register_or_get_user_by_email(email),
               {:ok, _identity} <-
                 %UserIdentity{}
                 |> UserIdentity.changeset(%{provider: provider, uid: uid, user_id: user.id})
                 |> Repo.insert() do
            {:ok, user}
          end
      end
    end)
  end
end

@doc "Returns all OAuth identities for the given user."
def list_user_identities(%User{} = user) do
  Repo.all_by(UserIdentity, user_id: user.id)
end

@doc "Returns the identity for a given provider and uid, or nil."
def get_identity_by_provider_uid(provider, uid) do
  Repo.get_by(UserIdentity, provider: provider, uid: uid)
end

@doc "Deletes an OAuth identity."
def delete_user_identity(%UserIdentity{} = identity) do
  Repo.delete(identity)
end
```

- [ ] **Step 8: Run the tests**

```bash
mix test test/speechwave/accounts_test.exs 2>&1 | grep -E "test|error|failure" | tail -20
```

Expected: the new `user_identities` describe block passes. Other tests may be failing due to removed password functions — that's OK, we'll fix in Task 15.

- [ ] **Step 9: Commit**

```bash
git add lib/speechwave/accounts/user_identity.ex lib/speechwave/accounts.ex priv/repo/migrations/ test/speechwave/accounts_test.exs
git commit -m "feat: add UserIdentity schema and OAuth find_or_create functions"
```

---

## Task 6: Simplify UserNotifier

**Files:**
- Modify: `lib/speechwave/accounts/user_notifier.ex`

- [ ] **Step 1: Replace the file**

The `deliver_login_instructions` currently branches on `confirmed_at` — remove that distinction. All magic links use the same email:

```elixir
defmodule Speechwave.Accounts.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  alias Speechwave.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Speechwave", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Deliver a magic link sign-in email."
  def deliver_login_instructions(user, url) do
    deliver(user.email, "Sign in to Speechwave", """

    ==============================

    Hi #{user.email},

    Click the link below to sign in to Speechwave. This link expires in 15 minutes.

    #{url}

    If you did not request this, you can safely ignore this email.

    ==============================
    """)
  end

  @doc "Deliver instructions to update a user email."
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
```

- [ ] **Step 2: Compile**

```bash
mix compile 2>&1 | grep error
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/speechwave/accounts/user_notifier.ex
git commit -m "refactor: simplify UserNotifier to single magic link email template"
```

---

## Task 7: Magic Link Controller Action + Router (Part 1)

Replace the two-step magic link flow (LiveView confirmation page) with a single controller action that logs the user in directly.

**Files:**
- Modify: `lib/speechwave_web/controllers/user_session_controller.ex`
- Modify: `lib/speechwave_web/router.ex`

- [ ] **Step 1: Replace UserSessionController with magic_link action only**

The old `create` action handled the two-step confirmation LiveView POST flow — that LiveView is being removed in Task 8, so `create` is dead code. Replace the entire `lib/speechwave_web/controllers/user_session_controller.ex` with:

```elixir
defmodule SpeechwaveWeb.UserSessionController do
  use SpeechwaveWeb, :controller

  alias Speechwave.Accounts
  alias SpeechwaveWeb.UserAuth

  @doc "Handles the magic link click — verifies token and creates a session directly."
  def magic_link(conn, %{"token" => token}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _tokens}} ->
        conn
        |> put_flash(:info, "Welcome!")
        |> UserAuth.log_in_user(user)

      {:error, _} ->
        conn
        |> put_flash(:error, "The sign-in link is invalid or has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
```

OAuth actions (`oauth_authorize`, `oauth_callback`) will be added in Task 9.

- [ ] **Step 2: Update the router**

In `lib/speechwave_web/router.ex`:

Remove from the authenticated scope:
```elixir
post "/users/update-password", UserSessionController, :update_password
```

The auth routes scope (`pipe_through [:browser]`) should now look like:

```elixir
scope "/", SpeechwaveWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
    live "/users/register", UserLive.Registration, :new
    live "/users/log-in", UserLive.Login, :new
  end

  get "/users/magic_link/:token", UserSessionController, :magic_link
  delete "/users/log-out", UserSessionController, :delete
end
```

Note: `post "/users/log-in"` is removed — nothing will POST there after the Confirmation LiveView is deleted in Task 8. The `confirm-email` route stays in the authenticated `live_session :require_authenticated_user` block since the email-change flow still uses it.

- [ ] **Step 3: Compile and run tests**

```bash
mix compile && mix test test/speechwave_web/controllers/user_session_controller_test.exs 2>&1 | tail -20
```

Expected: compilation passes. Some controller tests may fail (they test password login or update_password). We'll fix in Task 15.

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/controllers/user_session_controller.ex lib/speechwave_web/router.ex
git commit -m "feat: add magic_link controller action, remove update_password"
```

---

## Task 8: Delete Registration and Confirmation LiveViews

**Files:**
- Delete: `lib/speechwave_web/live/user_live/registration.ex`
- Delete: `lib/speechwave_web/live/user_live/confirmation.ex`
- Delete: `test/speechwave_web/live/user_live/registration_test.exs`
- Delete: `test/speechwave_web/live/user_live/confirmation_test.exs`
- Modify: `lib/speechwave_web/router.ex`

- [ ] **Step 1: Delete the files**

```bash
rm lib/speechwave_web/live/user_live/registration.ex
rm lib/speechwave_web/live/user_live/confirmation.ex
rm test/speechwave_web/live/user_live/registration_test.exs
rm test/speechwave_web/live/user_live/confirmation_test.exs
```

- [ ] **Step 2: Remove registration route from router**

In `lib/speechwave_web/router.ex`, remove:

```elixir
live "/users/register", UserLive.Registration, :new
```

The `live_session :current_user` block now only contains:

```elixir
live_session :current_user,
  on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
  live "/users/log-in", UserLive.Login, :new
end
```

- [ ] **Step 3: Compile**

```bash
mix compile 2>&1 | grep error
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove Registration and Confirmation LiveViews"
```

---

## Task 9: OAuth Controller Actions + Config

**Files:**
- Modify: `lib/speechwave_web/controllers/user_session_controller.ex`
- Modify: `lib/speechwave_web/router.ex`
- Modify: `config/runtime.exs`

- [ ] **Step 1: Add OAuth actions to UserSessionController**

Add the following actions to `lib/speechwave_web/controllers/user_session_controller.ex`:

```elixir
@doc "Initiates OAuth authorization for the given provider."
def oauth_authorize(conn, %{"provider" => provider}) do
  config = assent_config(provider, conn)

  case Assent.authorize_url(config) do
    {:ok, %{url: url, session_params: session_params}} ->
      conn
      |> put_session(:assent_session_params, session_params)
      |> put_session(:oauth_context, oauth_context(conn))
      |> redirect(external: url)

    {:error, _} ->
      conn
      |> put_flash(:error, "Authentication provider is not configured.")
      |> redirect(to: ~p"/users/log-in")
  end
end

@doc "Handles the OAuth provider callback."
def oauth_callback(conn, %{"provider" => provider} = params) do
  session_params = get_session(conn, :assent_session_params)
  config = assent_config(provider, conn)

  case Assent.callback(config, params, session_params) do
    {:ok, %{user: user_info}} ->
      context = get_session(conn, :oauth_context)
      current_user = conn.assigns.current_scope && conn.assigns.current_scope.user

      if context == "connect" && current_user do
        handle_oauth_connect(conn, provider, user_info, current_user)
      else
        handle_oauth_login(conn, provider, user_info)
      end

    {:error, _} ->
      conn
      |> put_flash(:error, "Authentication failed. Please try again.")
      |> redirect(to: ~p"/users/log-in")
  end
end

defp handle_oauth_login(conn, provider, user_info) do
  case Accounts.find_or_create_user_from_oauth(provider, user_info) do
    {:ok, user} ->
      conn
      |> delete_session(:assent_session_params)
      |> delete_session(:oauth_context)
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user)

    {:error, :email_not_verified} ->
      conn
      |> put_flash(:error, "Your #{provider} email address is not verified. Please verify it and try again.")
      |> redirect(to: ~p"/users/log-in")

    {:error, _} ->
      conn
      |> put_flash(:error, "Could not sign you in. Please try again.")
      |> redirect(to: ~p"/users/log-in")
  end
end

defp handle_oauth_connect(conn, provider, user_info, current_user) do
  uid = user_info["sub"]

  case Accounts.get_identity_by_provider_uid(provider, uid) do
    nil ->
      case Accounts.find_or_create_user_from_oauth(provider, user_info) do
        {:ok, _} ->
          conn
          |> delete_session(:assent_session_params)
          |> delete_session(:oauth_context)
          |> put_flash(:info, "#{String.capitalize(provider)} account connected.")
          |> redirect(to: ~p"/users/settings")

        {:error, _} ->
          conn
          |> put_flash(:error, "Could not connect your #{provider} account.")
          |> redirect(to: ~p"/users/settings")
      end

    existing_identity ->
      if existing_identity.user_id == current_user.id do
        conn
        |> put_flash(:info, "#{String.capitalize(provider)} is already connected to your account.")
        |> redirect(to: ~p"/users/settings")
      else
        conn
        |> put_flash(:error, "This #{provider} account is linked to a different Speechwave account.")
        |> redirect(to: ~p"/users/settings")
      end
  end
end

defp oauth_context(conn) do
  if conn.assigns.current_scope && conn.assigns.current_scope.user do
    "connect"
  else
    "login"
  end
end

defp assent_config(provider, conn) do
  provider_atom = String.to_existing_atom(provider)
  base_config = Application.get_env(:speechwave, :oauth_providers, [])[provider_atom] || []
  redirect_uri = url(conn, ~p"/auth/#{provider}/callback")
  Keyword.put(base_config, :redirect_uri, redirect_uri)
end
```

- [ ] **Step 2: Add OAuth routes to router**

In `lib/speechwave_web/router.ex`, add a new scope for OAuth routes that works with or without authentication:

```elixir
# OAuth routes — accessible authenticated or not (login + connect flows)
scope "/auth", SpeechwaveWeb do
  pipe_through :browser

  get "/:provider", UserSessionController, :oauth_authorize
  get "/:provider/callback", UserSessionController, :oauth_callback
end
```

Place this after the existing auth scope block.

- [ ] **Step 3: Add Assent provider config to runtime.exs**

In `config/runtime.exs`, add after the existing config blocks:

```elixir
# OAuth provider configuration
# Set these environment variables to enable each provider.
# For local dev, register an app with each provider using http://localhost:4000 as the redirect base.
# Note: verify the Microsoft strategy module name with the Assent docs (AzureAD or Microsoft).
oauth_providers =
  [
    google:
      if(client_id = System.get_env("GOOGLE_CLIENT_ID"),
        do: [
          client_id: client_id,
          client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
          strategy: Assent.Strategy.Google
        ]
      ),
    github:
      if(client_id = System.get_env("GITHUB_CLIENT_ID"),
        do: [
          client_id: client_id,
          client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
          strategy: Assent.Strategy.Github
        ]
      ),
    microsoft:
      if(client_id = System.get_env("MICROSOFT_CLIENT_ID"),
        do: [
          client_id: client_id,
          client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
          tenant_id: System.get_env("MICROSOFT_TENANT_ID", "common"),
          strategy: Assent.Strategy.AzureAD
        ]
      )
  ]
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)

config :speechwave, :oauth_providers, oauth_providers
```

> **Note on Microsoft:** Check the Assent docs (`mix hex.docs open assent`) for the exact module name — it may be `Assent.Strategy.Microsoft` instead of `Assent.Strategy.AzureAD`. Search for "microsoft" in the Assent source: `grep -r "microsoft\|azure" deps/assent/lib --include="*.ex" -li`

- [ ] **Step 4: Compile**

```bash
mix compile 2>&1 | grep error
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/controllers/user_session_controller.ex lib/speechwave_web/router.ex config/runtime.exs
git commit -m "feat: add OAuth controller actions and Assent configuration"
```

---

## Task 10: Update Login LiveView

Remove the password form, update magic link to auto-register users, add OAuth buttons, and update the magic link URL.

**Files:**
- Modify: `lib/speechwave_web/live/user_live/login.ex`

- [ ] **Step 1: Replace the Login LiveView**

```elixir
defmodule SpeechwaveWeb.UserLive.Login do
  use SpeechwaveWeb, :live_view

  alias Speechwave.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-6">
        <div class="text-center">
          <.header>
            Sign in to Speechwave
            <:subtitle>Enter your email to receive a sign-in link</:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>Running the local mail adapter.</p>
            <p>
              Sign-in links appear at <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <%= if @link_sent do %>
          <div id="magic-link-sent" class="text-center space-y-2">
            <p class="font-medium">Check your inbox</p>
            <p class="text-sm text-base-content/70">
              We sent a sign-in link to <strong>{@submitted_email}</strong>.
              It expires in 15 minutes.
            </p>
            <.link navigate={~p"/users/log-in"} class="text-sm underline">
              Try a different email
            </.link>
          </div>
        <% else %>
          <.form
            for={@form}
            id="magic-link-form"
            phx-submit="submit_magic"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full" phx-disable-with="Sending…">
              Send sign-in link <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <div class="divider text-sm">or continue with</div>

          <div id="oauth-buttons" class="flex flex-col gap-3">
            <.link
              :if={oauth_provider_configured?(:google)}
              href={~p"/auth/google"}
              class="btn btn-outline w-full"
            >
              <.icon name="hero-globe-alt" class="size-5" /> Google
            </.link>
            <.link
              :if={oauth_provider_configured?(:microsoft)}
              href={~p"/auth/microsoft"}
              class="btn btn-outline w-full"
            >
              <.icon name="hero-building-office" class="size-5" /> Microsoft
            </.link>
            <.link
              :if={oauth_provider_configured?(:github)}
              href={~p"/auth/github"}
              class="btn btn-outline w-full"
            >
              <.icon name="hero-code-bracket" class="size-5" /> GitHub
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: "user")
    {:ok, assign(socket, form: form, link_sent: false, submitted_email: nil)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case Accounts.register_or_get_user_by_email(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/magic_link/#{&1}"))

      {:error, _} ->
        nil
    end

    {:noreply, assign(socket, link_sent: true, submitted_email: email)}
  end

  defp local_mail_adapter? do
    Application.get_env(:speechwave, Speechwave.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  defp oauth_provider_configured?(provider) do
    providers = Application.get_env(:speechwave, :oauth_providers, [])
    Keyword.has_key?(providers, provider) && providers[provider] != nil
  end
end
```

- [ ] **Step 2: Compile**

```bash
mix compile 2>&1 | grep error
```

Expected: no errors.

- [ ] **Step 3: Run the login LiveView test**

```bash
mix test test/speechwave_web/live/user_live/login_test.exs 2>&1 | tail -20
```

Expected: some tests pass, some fail (they test password forms that no longer exist). We'll update these tests in Task 15.

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/live/user_live/login.ex
git commit -m "feat: redesign login page — magic link + OAuth, remove password form"
```

---

## Task 11: Update Settings LiveView

Remove the password section and add a "Connected accounts" section for OAuth identity management.

**Files:**
- Modify: `lib/speechwave_web/live/user_live/settings.ex`

- [ ] **Step 1: Replace the Settings LiveView**

```elixir
defmodule SpeechwaveWeb.UserLive.Settings do
  use SpeechwaveWeb, :live_view

  on_mount {SpeechwaveWeb.UserAuth, :require_sudo_mode}

  alias Speechwave.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your email and connected accounts</:subtitle>
        </.header>
      </div>

      <%!-- Email section --%>
      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <%!-- Connected OAuth accounts --%>
      <div id="connected-accounts" class="space-y-4">
        <h3 class="font-semibold text-base-content">Connected accounts</h3>
        <p class="text-sm text-base-content/70">
          Sign in faster using a linked account. Magic link is always available as a fallback.
        </p>

        <div class="space-y-2">
          <%= for provider <- ["google", "microsoft", "github"] do %>
            <% identity = Enum.find(@identities, &(&1.provider == provider)) %>
            <div id={"identity-#{provider}"} class="flex items-center justify-between p-3 rounded-lg border border-base-300">
              <span class="font-medium capitalize">{provider}</span>
              <%= if identity do %>
                <button
                  id={"disconnect-#{provider}"}
                  phx-click="disconnect_identity"
                  phx-value-id={identity.id}
                  data-confirm={"Disconnect your #{provider} account?"}
                  class="text-sm text-error hover:underline"
                >
                  Disconnect
                </button>
              <% else %>
                <.link
                  id={"connect-#{provider}"}
                  href={~p"/auth/#{provider}"}
                  class="text-sm text-primary hover:underline"
                >
                  Connect
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <div class="divider" />

      <%!-- API Key section --%>
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
            phx-hook=".SelectOnClick"
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
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SelectOnClick">
      export default {
        mounted() { this.el.addEventListener("click", () => this.el.select()) }
      }
    </script>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:api_key, user.api_key)
      |> assign(:identities, Accounts.list_user_identities(user))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("disconnect_identity", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    identity = Enum.find(socket.assigns.identities, &(to_string(&1.id) == id))

    if identity && identity.user_id == user.id do
      {:ok, _} = Accounts.delete_user_identity(identity)
      {:noreply, assign(socket, :identities, Accounts.list_user_identities(user))}
    else
      {:noreply, put_flash(socket, :error, "Could not disconnect that account.")}
    end
  end

  def handle_event("regenerate_api_key", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, updated_user} = Accounts.regenerate_api_key(user)

    SpeechwaveWeb.Endpoint.broadcast!("user:#{user.id}:disconnect", "disconnect", %{})

    {:noreply, assign(socket, :api_key, updated_user.api_key)}
  end
end
```

- [ ] **Step 2: Compile and run settings tests**

```bash
mix compile && mix test test/speechwave_web/live/user_live/settings_test.exs 2>&1 | tail -20
```

Expected: some tests pass, some fail (they test password forms). We'll update in Task 15.

- [ ] **Step 3: Commit**

```bash
git add lib/speechwave_web/live/user_live/settings.ex
git commit -m "feat: update settings page — remove password section, add connected accounts"
```

---

## Task 12: Dev Login Backdoor

**Files:**
- Create: `lib/speechwave_web/controllers/dev_login_controller.ex`
- Modify: `lib/speechwave_web/router.ex`

- [ ] **Step 1: Create the dev login controller**

Create `lib/speechwave_web/controllers/dev_login_controller.ex`:

```elixir
defmodule SpeechwaveWeb.DevLoginController do
  use SpeechwaveWeb, :controller

  alias Speechwave.Accounts
  alias SpeechwaveWeb.UserAuth

  def index(conn, _params) do
    users = Speechwave.Repo.all(Accounts.User)
    render(conn, :index, users: users)
  end

  def create(conn, %{"email" => email}) when byte_size(email) > 0 do
    {:ok, user} = Accounts.register_or_get_user_by_email(email)

    conn
    |> put_flash(:info, "Logged in as #{user.email}")
    |> UserAuth.log_in_user(user)
  end

  def create(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(String.to_integer(user_id))

    conn
    |> put_flash(:info, "Logged in as #{user.email}")
    |> UserAuth.log_in_user(user)
  end
end
```

- [ ] **Step 2: Create the dev login template**

Create `lib/speechwave_web/controllers/dev_login_html/index.html.heex`:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="mx-auto max-w-sm space-y-6">
    <.header>Dev Login</.header>

    <.form for={%{}} action={~p"/dev/login"} method="post" id="dev-freeform-form">
      <.input name="email" type="email" label="Any email (creates account if new)" value="" />
      <.button class="w-full">Log in</.button>
    </.form>

    <div class="divider">Existing users</div>

    <div id="dev-user-list" class="space-y-2">
      <%= for user <- @users do %>
        <.form for={%{}} action={~p"/dev/login"} method="post" id={"dev-user-#{user.id}"}>
          <input type="hidden" name="user_id" value={user.id} />
          <button type="submit" class="w-full text-left px-3 py-2 rounded border border-base-300 hover:bg-base-200 text-sm">
            {user.email}
            <span class="text-base-content/50 ml-2">{user.plan}</span>
            <%= if user.is_admin do %>
              <span class="text-primary ml-1">admin</span>
            <% end %>
          </button>
        </.form>
      <% end %>
    </div>
  </div>
</Layouts.app>
```

- [ ] **Step 3: Create the DevLoginHTML view module**

Create `lib/speechwave_web/controllers/dev_login_html.ex`:

```elixir
defmodule SpeechwaveWeb.DevLoginHTML do
  use SpeechwaveWeb, :html

  embed_templates "dev_login_html/*"
end
```

- [ ] **Step 4: Add dev login routes to router**

In `lib/speechwave_web/router.ex`, inside the `if Application.compile_env(:speechwave, :dev_routes) do` block:

```elixir
if Application.compile_env(:speechwave, :dev_routes) do
  import Phoenix.LiveDashboard.Router

  scope "/dev" do
    pipe_through :browser

    live_dashboard "/dashboard", metrics: SpeechwaveWeb.Telemetry
    forward "/mailbox", Plug.Swoosh.MailboxPreview
    get "/login", DevLoginController, :index
    post "/login", DevLoginController, :create
  end
end
```

- [ ] **Step 5: Compile and verify**

```bash
mix compile 2>&1 | grep error
```

Expected: no errors.

- [ ] **Step 6: Start the server and manually test the dev login**

```bash
mix phx.server
```

Navigate to `http://localhost:4000/dev/login`, enter an email, verify you are logged in and redirected.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave_web/controllers/dev_login_controller.ex \
        lib/speechwave_web/controllers/dev_login_html.ex \
        lib/speechwave_web/controllers/dev_login_html/ \
        lib/speechwave_web/router.ex
git commit -m "feat: add dev login backdoor at /dev/login"
```

---

## Task 13: Update Seeds

**Files:**
- Modify: `priv/repo/seeds.exs`

- [ ] **Step 1: Replace seeds.exs**

```elixir
# priv/repo/seeds.exs
#
# Run with: mix run priv/repo/seeds.exs
# Idempotent: safe to run multiple times.

alias Speechwave.{Accounts, Repo}

admin_email = System.get_env("ADMIN_EMAIL") || "admin@speechwave.live"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, user} = Accounts.register_user(%{email: admin_email})
    Repo.update!(Ecto.Changeset.change(user, is_admin: true))
    IO.puts("Admin user created: #{admin_email}")

  existing ->
    unless existing.is_admin do
      Repo.update!(Ecto.Changeset.change(existing, is_admin: true))
    end

    IO.puts("Admin user confirmed: #{existing.email}")
end
```

- [ ] **Step 2: Reset and reseed to verify**

```bash
mix ecto.reset
```

Expected: database created, migrated, and seeded without errors. No ADMIN_PASSWORD needed.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/seeds.exs
git commit -m "fix: update seeds to use email-only admin (no password)"
```

---

## Task 14: Fix Tests

The existing test suite has tests for password login, registration, confirmation, and password update that no longer apply. This task cleans those up and fixes the test fixtures.

**Files:**
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Modify: `test/speechwave/accounts_test.exs`
- Modify: `test/speechwave_web/controllers/user_session_controller_test.exs`
- Modify: `test/speechwave_web/live/user_live/login_test.exs`
- Modify: `test/speechwave_web/live/user_live/settings_test.exs`

- [ ] **Step 1: Update accounts_fixtures.ex**

Replace `test/support/fixtures/accounts_fixtures.ex`:

```elixir
defmodule Speechwave.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Speechwave.Accounts` context.
  """

  import Ecto.Query

  alias Speechwave.Accounts
  alias Speechwave.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{email: unique_user_email()})
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Speechwave.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Speechwave.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Speechwave.Repo.update_all(
      from(t in Accounts.UserToken, where: t.token == ^token),
      set: [authenticated_at: authenticated_at]
    )
  end

  def oauth_user_fixture(attrs \\ %{}) do
    email = Keyword.get(attrs, :email, unique_user_email())
    provider = Keyword.get(attrs, :provider, "google")
    uid = Keyword.get(attrs, :uid, "uid-#{System.unique_integer()}")

    {:ok, user} =
      Accounts.find_or_create_user_from_oauth(provider, %{
        "sub" => uid,
        "email" => email,
        "email_verified" => true
      })

    user
  end
end
```

- [ ] **Step 2: Update accounts_test.exs**

Remove test blocks that are no longer valid. Delete or comment out these describe blocks:
- `describe "get_user_by_email_and_password/2"` — function deleted
- `describe "change_user_password/3"` (if exists) — function deleted
- `describe "update_user_password/2"` (if exists) — function deleted

Also remove `valid_user_password/0` and `set_password/1` references in existing tests.

Run the accounts tests to see what's failing:

```bash
mix test test/speechwave/accounts_test.exs 2>&1 | grep -E "^\s+\*\*|test "
```

For each failing test, either:
- Delete it if it tests removed functionality (passwords)
- Update it if it tests still-valid functionality (session tokens, email change, magic links)

The following tests should continue to pass after cleanup:
- `get_user_by_email/1` tests
- `register_user/1` tests (the non-password parts)
- `get_user!/1` tests
- `deliver_login_instructions/2` tests
- `login_user_by_magic_link/1` tests  
- `get_user_by_session_token/1` tests
- `delete_user_session_token/1` tests
- `user_identities` tests (added in Task 5)

- [ ] **Step 3: Update user_session_controller_test.exs**

Run the tests to see what fails:

```bash
mix test test/speechwave_web/controllers/user_session_controller_test.exs 2>&1 | tail -30
```

Remove tests for:
- Password-based login (`POST /users/log-in` with email+password)
- `update_password` action

Add a test for the magic link controller action:

```elixir
describe "magic_link/2" do
  test "logs in via valid token", %{conn: conn} do
    user = user_fixture()
    {token, _} = generate_user_magic_link_token(user)

    conn = get(conn, ~p"/users/magic_link/#{token}")

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
  end

  test "redirects to login on invalid token", %{conn: conn} do
    conn = get(conn, ~p"/users/magic_link/invalid-token")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
  end
end
```

- [ ] **Step 4: Update login_test.exs**

Run to see failures:

```bash
mix test test/speechwave_web/live/user_live/login_test.exs 2>&1 | tail -30
```

Remove tests for:
- Password form rendering
- Password form submission
- `submit_password` event

Update or add tests for:
- Magic link form renders
- Submitting email shows "check your inbox" confirmation
- OAuth buttons render (when providers configured)

```elixir
describe "login page" do
  test "renders the magic link form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")
    assert has_element?(view, "#magic-link-form")
  end

  test "shows confirmation after email submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    view
    |> form("#magic-link-form", %{"user" => %{"email" => "test@example.com"}})
    |> render_submit()

    assert has_element?(view, "#magic-link-sent")
  end
end
```

- [ ] **Step 5: Update settings_test.exs**

Run to see failures:

```bash
mix test test/speechwave_web/live/user_live/settings_test.exs 2>&1 | tail -30
```

Remove tests for:
- Password form rendering
- Password validation/update events

Add tests for:
- Connected accounts section renders
- Disconnect identity works

```elixir
describe "connected accounts" do
  setup :register_and_log_in_user

  test "shows connected accounts section", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")
    assert has_element?(view, "#connected-accounts")
  end

  test "disconnect removes an identity", %{conn: conn, user: user} do
    {:ok, _} =
      Speechwave.Accounts.find_or_create_user_from_oauth("google", %{
        "sub" => "g-test-uid",
        "email" => user.email,
        "email_verified" => true
      })

    {:ok, view, _html} = live(conn, ~p"/users/settings")
    assert has_element?(view, "#disconnect-google")

    view
    |> element("#disconnect-google")
    |> render_click()

    refute has_element?(view, "#disconnect-google")
  end
end
```

- [ ] **Step 6: Run the full test suite**

```bash
mix test 2>&1 | tail -20
```

Fix any remaining test failures. Common issues:
- `unconfirmed_user_fixture` removed — replace any remaining usages with `user_fixture`
- `set_password` helper removed — remove any test that calls it
- Missing `import Speechwave.AccountsFixtures` — check test files import the fixtures module

- [ ] **Step 7: Run precommit**

```bash
mix precommit
```

Fix any issues reported.

- [ ] **Step 8: Commit**

```bash
git add test/
git commit -m "test: update test suite for passwordless auth"
```

---

## Task 15: Verify End-to-End Flow

Manual verification before considering the feature complete.

- [ ] **Step 1: Reset the dev database and start the server**

```bash
mix ecto.reset && mix phx.server
```

- [ ] **Step 2: Test magic link login**

1. Visit `http://localhost:4000/users/log-in`
2. Enter a new email address and click "Send sign-in link"
3. Verify the confirmation message appears ("Check your inbox")
4. Visit `http://localhost:4000/dev/mailbox`
5. Open the email and click the sign-in link
6. Verify you are logged in and redirected to `/`

- [ ] **Step 3: Test magic link with existing user**

Repeat Step 2 with the same email — should log in to the same account.

- [ ] **Step 4: Test dev login backdoor**

1. Log out
2. Visit `http://localhost:4000/dev/login`
3. Click an existing user → verify logged in
4. Log out, enter a new email in the freeform field → verify new account created

- [ ] **Step 5: Test settings page**

1. Log in, visit `/users/settings`
2. Verify no password form
3. Verify "Connected accounts" section shows Google/Microsoft/GitHub (with Connect links)

- [ ] **Step 6: Test expired magic link**

1. Generate a link and let it expire (or manually expire the token in the DB via Tidewave)
2. Try to use it — verify redirect to login with error flash

- [ ] **Step 7: Final commit if any manual fixes were needed**

```bash
mix precommit
git add -A
git commit -m "fix: post-integration fixes from manual testing"
```
