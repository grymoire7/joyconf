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
end
