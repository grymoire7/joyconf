defmodule JoyconfWeb.ReactionChannelTest do
  use JoyconfWeb.ChannelCase

  setup do
    {:ok, talk} = Joyconf.Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    {:ok, socket} = connect(JoyconfWeb.UserSocket, %{})
    {:ok, socket: socket, talk: talk}
  end

  test "joins channel for existing talk", %{socket: socket, talk: talk} do
    assert {:ok, _, _socket} = subscribe_and_join(socket, "reactions:#{talk.slug}", %{})
  end

  test "rejects join for unknown talk", %{socket: socket} do
    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, "reactions:nonexistent", %{})
  end

  test "pushes new_reaction to client when Endpoint broadcasts", %{socket: socket, talk: talk} do
    {:ok, _, _socket} = subscribe_and_join(socket, "reactions:#{talk.slug}", %{})
    JoyconfWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "❤️"})
    assert_push "new_reaction", %{emoji: "❤️"}
  end
end
