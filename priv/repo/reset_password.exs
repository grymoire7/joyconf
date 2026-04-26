# Reset a user's password.
#
# Usage:
#   mix run priv/repo/reset_password.exs <email> <new_password>

[email, password] = System.argv()

alias Speechwave.{Accounts, Repo}

case Accounts.get_user_by_email(email) do
  nil ->
    IO.puts("Error: no user found with email #{email}")
    System.halt(1)

  user ->
    user
    |> Accounts.User.password_changeset(%{password: password}, hash_password: true)
    |> Repo.update!()

    IO.puts("Password updated for #{email}")
end
