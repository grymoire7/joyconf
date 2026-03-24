defmodule JoyconfWeb.AdminAuth do
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts
  def call(conn, opts), do: require_admin(conn, opts)

  def require_admin(conn, _opts) do
    password = Application.get_env(:joyconf, :admin_password)

    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [_user, ^password] <- String.split(decoded, ":", parts: 2) do
      conn
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="JoyConf Admin"))
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end
end
