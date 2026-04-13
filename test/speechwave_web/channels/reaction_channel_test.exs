defmodule SpeechwaveWeb.ReactionChannelTest do
  use SpeechwaveWeb.ChannelCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  setup do
    user = user_fixture()
    talk = talk_fixture(user, %{title: "Test Talk", slug: "test-talk"})
    {:ok, socket} = connect(SpeechwaveWeb.UserSocket, %{})
    {:ok, socket: socket, talk: talk, user: user}
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
    SpeechwaveWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "❤️"})
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
      assert Speechwave.Talks.get_session(session_id) != nil
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

      session = Speechwave.Talks.get_session(session_id)
      assert session.ended_at != nil
    end

    test "stop_session returns error for an unknown session_id", %{joined: joined} do
      ref = push(joined, "stop_session", %{"session_id" => 999_999})
      assert_reply ref, :error, %{reason: "not_found"}
    end

    test "stop_session returns error for a session belonging to a different talk",
         %{joined: joined, user: user} do
      other_talk = talk_fixture(user, %{title: "Other", slug: "other-#{System.unique_integer()}"})
      {:ok, other_session} = Speechwave.Talks.start_session(other_talk)

      ref = push(joined, "stop_session", %{"session_id" => other_session.id})
      assert_reply ref, :error, %{reason: "unauthorized"}
    end

    test "stop_session is idempotent — does not overwrite ended_at on an already-stopped session",
         %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id}

      ref2 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref2, :ok
      first_end = Speechwave.Talks.get_session(session_id).ended_at

      ref3 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref3, :ok
      second_end = Speechwave.Talks.get_session(session_id).ended_at

      assert first_end == second_end
    end

    test "rejects start_session when monthly full-session limit is reached",
         %{joined: joined, talk: talk} do
      # Seed 10 completed full sessions (> 10 min) to hit the free tier limit
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      full_end = DateTime.add(now, 15 * 60, :second)

      for i <- 1..10 do
        Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
          talk_id: talk.id,
          label: "Seed #{i}",
          started_at: now,
          ended_at: full_end
        })
      end

      ref = push(joined, "start_session", %{})
      assert_reply ref, :error, %{reason: "session_limit_reached"}
    end

  end

  describe "slide_changed" do
    setup %{socket: socket, talk: talk} do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "slides:#{talk.slug}")
      {:ok, _, joined} = subscribe_and_join(socket, "reactions:#{talk.slug}", %{})
      %{joined: joined, talk: talk}
    end

    test "broadcasts slide number to the slides PubSub topic", %{joined: joined} do
      ref = push(joined, "slide_changed", %{"slide" => 5})
      assert_reply ref, :ok

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: "slides:" <> _slug,
                       event: "slide_changed",
                       payload: %{slide: 5}
                     },
                     500
    end

    test "does not broadcast for slide 0 (unknown slide sentinel)", %{joined: joined} do
      ref = push(joined, "slide_changed", %{"slide" => 0})
      assert_reply ref, :ok
      refute_receive %Phoenix.Socket.Broadcast{event: "slide_changed"}, 200
    end
  end
end
