defmodule JoyconfWeb.TalkLiveTest do
  use JoyconfWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    {:ok, talk} =
      Joyconf.Talks.create_talk(%{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})

    {:ok, talk: talk}
  end

  test "renders the talk page with emoji buttons", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    assert has_element?(view, "#emoji-buttons")
    assert render(view) =~ "❤️"
    assert render(view) =~ "😂"
    assert render(view) =~ "🙋🏻"
    assert render(view) =~ "👏"
    assert render(view) =~ "🤯"
  end

  test "redirects for unknown slug", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, "/t/nonexistent")
  end

  test "react event broadcasts via Endpoint when rate limit allows", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    Phoenix.PubSub.subscribe(Joyconf.PubSub, "reactions:#{talk.slug}")

    render_click(view, "react", %{"emoji" => "❤️"})

    assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}, 500
  end

  test "react event is silently dropped when rate limited", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    Phoenix.PubSub.subscribe(Joyconf.PubSub, "reactions:#{talk.slug}")

    render_click(view, "react", %{"emoji" => "❤️"})
    assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}, 500

    render_click(view, "react", %{"emoji" => "❤️"})
    refute_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 200
  end

  test "receives Endpoint broadcast and page still renders correctly", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    JoyconfWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "🔥"})
    assert render(view) =~ talk.title
  end
end
