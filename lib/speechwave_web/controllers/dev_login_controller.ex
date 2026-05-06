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
