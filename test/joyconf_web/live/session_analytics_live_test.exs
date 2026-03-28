defmodule JoyconfWeb.SessionAnalyticsLiveTest do
  use JoyconfWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    Application.put_env(:joyconf, :admin_password, "testpassword")

    authed =
      put_req_header(conn, "authorization", "Basic " <> Base.encode64("admin:testpassword"))

    {:ok, conn: authed}
  end

  setup do
    {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    {:ok, session} = Joyconf.Talks.start_session(talk)
    {:ok, talk: talk, session: session}
  end

  test "renders session label and talk title", %{conn: conn, talk: talk, session: session} do
    {:ok, _view, html} = live(conn, "/admin/sessions/#{session.id}")
    assert html =~ session.label
    assert html =~ talk.title
  end

  test "shows total reaction count", %{conn: conn, session: session} do
    Joyconf.Reactions.create_reaction(session, "❤️", 1)
    Joyconf.Reactions.create_reaction(session, "😂", 1)
    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}")
    assert has_element?(view, "#total-reactions", "2")
  end

  test "renders a row for each slide that has reactions", %{conn: conn, session: session} do
    Joyconf.Reactions.create_reaction(session, "❤️", 1)
    Joyconf.Reactions.create_reaction(session, "❤️", 3)
    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}")
    assert has_element?(view, "#slide-row-1")
    assert has_element?(view, "#slide-row-3")
    refute has_element?(view, "#slide-row-2")
  end

  test "labels slide 0 as General", %{conn: conn, session: session} do
    Joyconf.Reactions.create_reaction(session, "❤️", 0)
    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}")
    assert has_element?(view, "#slide-row-0", "General")
  end

  test "shows compare link when talk has multiple sessions", %{
    conn: conn,
    talk: talk,
    session: session
  } do
    {:ok, s1} = Joyconf.Talks.stop_session(session)
    {:ok, _s2} = Joyconf.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/admin/sessions/#{s1.id}")
    assert has_element?(view, "#compare-link")
  end

  test "redirects to admin when session id is unknown", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/sessions/999999")
  end

  test "redirects to admin for non-integer session id", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/sessions/notanumber")
  end

  test "renders compare section when compare_session param is present",
       %{conn: conn, talk: talk, session: session} do
    {:ok, _} = Joyconf.Talks.stop_session(session)
    {:ok, s2} = Joyconf.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/admin/sessions/#{session.id}/compare/#{s2.id}")
    assert has_element?(view, "#compare-section")
    assert render(view) =~ session.label
    assert render(view) =~ s2.label
  end
end
