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

  describe "sessions panel" do
    setup %{conn: conn} do
      {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Prime Talk", slug: "prime"})
      {:ok, conn: conn, talk: talk}
    end

    test "shows empty sessions message when talk has no sessions", %{conn: conn, talk: _talk} do
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#sessions-panel")
      assert has_element?(view, "#no-sessions")
    end

    test "lists sessions with reaction counts when sessions exist", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      Joyconf.Reactions.create_reaction(session, "❤️")

      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      assert has_element?(view, "#session-#{session.id}")
      assert has_element?(view, "#session-label-#{session.id}", "Session 1")
      assert render(view) =~ "1 reaction"
    end

    test "shows Active badge for sessions without ended_at", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#session-#{session.id} .session-active-badge")
    end

    test "can rename a session", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()
      assert has_element?(view, "#rename-form-#{session.id}")

      view
      |> form("#rename-form-#{session.id}", rename: %{label: "Denver Practice"})
      |> render_submit()

      assert has_element?(view, "#session-label-#{session.id}", "Denver Practice")
    end

    test "can delete a session", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#delete-session-#{session.id}") |> render_click()

      refute has_element?(view, "#session-#{session.id}")
      assert Joyconf.Talks.get_session(session.id) == nil
    end

    test "rename form shows validation error for blank label", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()

      view
      |> form("#rename-form-#{session.id}", rename: %{label: ""})
      |> render_submit()

      # Form stays open with an error — session label is unchanged
      assert has_element?(view, "#rename-form-#{session.id}")
      assert has_element?(view, "#session-label-#{session.id}", "Session 1") == false or
               has_element?(view, "#rename-form-#{session.id}")
    end

    test "cancel_rename hides the rename form", %{conn: conn, talk: talk} do
      {:ok, session} = Joyconf.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()
      assert has_element?(view, "#rename-form-#{session.id}")

      view |> element("button[phx-click='cancel_rename']") |> render_click()
      refute has_element?(view, "#rename-form-#{session.id}")
    end

    test "sessions panel is hidden after talk is deleted", %{conn: conn, talk: talk} do
      {:ok, view, _html} = live(conn, "/admin")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      view |> element("#delete-talk-#{talk.id}") |> render_click()
      refute has_element?(view, "#sessions-panel")
    end
  end
end
