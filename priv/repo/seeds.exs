# priv/repo/seeds.exs
#
# Run with: mix run priv/repo/seeds.exs
# Idempotent: safe to run multiple times.

alias Speechwave.{Accounts, Repo}

admin_email = System.get_env("ADMIN_EMAIL") || "admin@speechwave.live"
admin_password = System.fetch_env!("ADMIN_PASSWORD")

seed_admin = fn user ->
  confirmed_user =
    Repo.update!(
      Ecto.Changeset.change(user, confirmed_at: DateTime.utc_now(:second), is_admin: true)
    )

  {:ok, _} = Accounts.update_user_password(confirmed_user, %{password: admin_password})
end

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, user} = Accounts.register_user(%{email: admin_email})
    seed_admin.(user)
    IO.puts("Admin user created: #{admin_email}")

  existing ->
    seed_admin.(existing)
    IO.puts("Admin user updated: #{existing.email}")
end
