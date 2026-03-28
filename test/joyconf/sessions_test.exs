defmodule Joyconf.SessionsTest do
  use Joyconf.DataCase

  alias Joyconf.Talks
  alias Joyconf.Talks.TalkSession

  setup do
    {:ok, talk} = Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    %{talk: talk}
  end

  describe "TalkSession.changeset/2" do
    test "valid with label and started_at" do
      cs =
        TalkSession.changeset(%TalkSession{}, %{
          label: "Session 1",
          started_at: ~U[2026-01-01 10:00:00Z]
        })

      assert cs.valid?
    end

    test "requires label" do
      cs = TalkSession.changeset(%TalkSession{}, %{started_at: ~U[2026-01-01 10:00:00Z]})
      assert "can't be blank" in errors_on(cs).label
    end

    test "requires started_at" do
      cs = TalkSession.changeset(%TalkSession{}, %{label: "Session 1"})
      assert "can't be blank" in errors_on(cs).started_at
    end
  end

  describe "start_session/1" do
    test "creates a session labeled 'Session 1' for a new talk", %{talk: talk} do
      assert {:ok, session} = Talks.start_session(talk)
      assert session.label == "Session 1"
      assert session.talk_id == talk.id
      assert session.started_at != nil
      assert session.ended_at == nil
    end

    test "labels the second session 'Session 2'", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      {:ok, _} = Talks.stop_session(s1)
      assert {:ok, s2} = Talks.start_session(talk)
      assert s2.label == "Session 2"
    end

    test "returns the existing session when one is already active", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      assert {:ok, s2} = Talks.start_session(talk)
      assert s1.id == s2.id
    end
  end

  describe "stop_session/1" do
    test "sets ended_at on the session", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, stopped} = Talks.stop_session(session)
      assert stopped.ended_at != nil
    end
  end

  describe "get_active_session/1" do
    test "returns the active session when one exists", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert Talks.get_active_session(talk.id).id == session.id
    end

    test "returns nil when no session has been started", %{talk: talk} do
      assert Talks.get_active_session(talk.id) == nil
    end

    test "returns nil after the session is stopped", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      Talks.stop_session(session)
      assert Talks.get_active_session(talk.id) == nil
    end
  end

  describe "get_session/1 and get_session!/1" do
    test "get_session/1 returns the session by id", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert Talks.get_session(session.id).id == session.id
    end

    test "get_session/1 returns nil for unknown id" do
      assert Talks.get_session(999_999) == nil
    end

    test "get_session!/1 raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Talks.get_session!(999_999) end
    end
  end
end
