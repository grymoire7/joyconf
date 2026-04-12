defmodule SpeechwaveWeb.PageController do
  use SpeechwaveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
