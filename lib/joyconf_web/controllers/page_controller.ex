defmodule JoyconfWeb.PageController do
  use JoyconfWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
