defmodule JoyconfWeb.AdminLiveTest do
  use JoyconfWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    Application.put_env(:joyconf, :admin_password, "testpassword")

    authed =
      put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:testpassword"))

    {:ok, conn: authed}
  end

  test "returns 401 without auth", %{conn: conn} do
    unauthed = delete_req_header(conn, "authorization")
    assert get(unauthed, "/admin").status == 401
  end

  test "renders new talk form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/talks/new")
    assert has_element?(view, "#talk-form")
  end

  test "auto-generates slug from title on validate", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/talks/new")

    view
    |> element("#talk-form")
    |> render_change(%{"talk" => %{"title" => "Elixir for Rubyists", "slug" => ""}})

    assert has_element?(view, "input[value='elixir-for-rubyists']")
  end

  test "creates talk, shows banner, and selects talk in list with QR code", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/talks/new")

    view
    |> form("#talk-form", talk: %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
    |> render_submit()

    assert has_element?(view, "#created-talk")
    refute has_element?(view, "#qr-code")
    assert has_element?(view, "#selected-talk-qr")
  end

  test "shows validation errors for blank fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/talks/new")
    view |> form("#talk-form", talk: %{title: "", slug: ""}) |> render_submit()
    assert has_element?(view, "#talk-form [data-errors]") or render(view) =~ "can&#39;t be blank"
  end

  test "lists existing talks on index", %{conn: conn} do
    {:ok, _} = Joyconf.Talks.create_talk(%{title: "My Talk", slug: "my-talk"})
    {:ok, _view, html} = live(conn, "/admin")
    assert html =~ "My Talk"
  end

  test "clicking a talk in the list shows its QR code", %{conn: conn} do
    {:ok, _} = Joyconf.Talks.create_talk(%{title: "Prime Talk", slug: "prime"})
    {:ok, view, _html} = live(conn, "/admin")

    view |> element("#talk-list button", "Prime Talk") |> render_click()

    assert has_element?(view, "#selected-talk-qr")
  end

  test "trashcan button appears next to selected talk", %{conn: conn} do
    {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Prime Talk", slug: "prime"})
    {:ok, view, _html} = live(conn, "/admin")

    view |> element("#talk-list button", "Prime Talk") |> render_click()

    assert has_element?(view, "#delete-talk-#{talk.id}")
  end

  test "clicking trashcan deletes the talk and removes it from the list", %{conn: conn} do
    {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Prime Talk", slug: "prime"})
    {:ok, view, _html} = live(conn, "/admin")

    view |> element("#talk-list button", "Prime Talk") |> render_click()
    view |> element("#delete-talk-#{talk.id}") |> render_click()

    refute has_element?(view, "#talk-list button", "Prime Talk")
  end
end
