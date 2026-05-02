defmodule SpeechwaveWeb.PageController do
  use SpeechwaveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def pricing(conn, _params), do: render(conn, :pricing)
  def terms(conn, _params), do: render(conn, :terms)
  def privacy(conn, _params), do: render(conn, :privacy)
end
