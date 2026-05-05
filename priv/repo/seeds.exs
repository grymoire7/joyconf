# priv/repo/seeds.exs
#
# Run with: mix run priv/repo/seeds.exs
# Idempotent: safe to run multiple times.

alias Speechwave.{Accounts, Repo}

admin_email = System.get_env("ADMIN_EMAIL") || "admin@speechwave.live"
admin_password = System.fetch_env!("ADMIN_PASSWORD")

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, user} = Accounts.register_user(%{email: admin_email, password: admin_password})
    Repo.update!(Ecto.Changeset.change(user, is_admin: true))
    IO.puts("Admin user created: #{admin_email}")

  existing ->
    {:ok, _} = Accounts.update_user_password(existing, %{password: admin_password})
    Repo.update!(Ecto.Changeset.change(existing, is_admin: true))
    IO.puts("Admin user updated: #{existing.email}")
end
