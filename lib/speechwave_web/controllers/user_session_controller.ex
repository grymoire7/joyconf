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
