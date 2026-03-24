defmodule JoyconfWeb.AdminAuthTest do
  use JoyconfWeb.ConnCase

  alias JoyconfWeb.AdminAuth

  setup do
    Application.put_env(:joyconf, :admin_password, "testpassword")
    :ok
  end

  test "allows request with correct password", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", basic_auth("admin", "testpassword"))
      |> AdminAuth.require_admin([])

    refute conn.halted
  end

  test "halts with 401 for wrong password", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", basic_auth("admin", "wrongpassword"))
      |> AdminAuth.require_admin([])

    assert conn.halted
    assert conn.status == 401
  end

  test "halts with 401 for missing authorization header", %{conn: conn} do
    conn = AdminAuth.require_admin(conn, [])
    assert conn.halted
    assert conn.status == 401
  end

  defp basic_auth(user, pass), do: "Basic " <> Base.encode64("#{user}:#{pass}")
end
