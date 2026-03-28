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

  describe "session management via channel" do
    setup %{socket: socket, talk: talk} do
      {:ok, _, joined} = subscribe_and_join(socket, "reactions:#{talk.slug}", %{})
      %{joined: joined, talk: talk}
    end

    test "start_session creates a session and replies with session_id and label",
         %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id, label: "Session 1"}
      assert Joyconf.Talks.get_session(session_id) != nil
    end

    test "start_session is idempotent when a session is already active",
         %{joined: joined} do
      ref1 = push(joined, "start_session", %{})
      assert_reply ref1, :ok, %{session_id: id1}

      ref2 = push(joined, "start_session", %{})
      assert_reply ref2, :ok, %{session_id: id2}

      assert id1 == id2
    end

    test "stop_session ends the active session", %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id}

      ref2 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref2, :ok

      session = Joyconf.Talks.get_session(session_id)
      assert session.ended_at != nil
    end

    test "stop_session returns error for an unknown session_id", %{joined: joined} do
      ref = push(joined, "stop_session", %{"session_id" => 999_999})
      assert_reply ref, :error, %{reason: "not_found"}
    end

    test "stop_session returns error for a session belonging to a different talk",
         %{joined: joined} do
      {:ok, other_talk} = Joyconf.Talks.create_talk(%{title: "Other", slug: "other"})
      {:ok, other_session} = Joyconf.Talks.start_session(other_talk)

      ref = push(joined, "stop_session", %{"session_id" => other_session.id})
      assert_reply ref, :error, %{reason: "unauthorized"}
    end

    test "stop_session is idempotent — does not overwrite ended_at on an already-stopped session",
         %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id}

      ref2 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref2, :ok
      first_end = Joyconf.Talks.get_session(session_id).ended_at

      ref3 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref3, :ok
      second_end = Joyconf.Talks.get_session(session_id).ended_at

      assert first_end == second_end
    end
  end
end
