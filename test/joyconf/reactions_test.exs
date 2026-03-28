defmodule Joyconf.ReactionsTest do
  use Joyconf.DataCase

  alias Joyconf.{Talks, Reactions}

  setup do
    {:ok, talk} = Talks.create_talk(%{title: "Test Talk", slug: "test-talk"})
    {:ok, session} = Talks.start_session(talk)
    %{session: session}
  end

  describe "create_reaction/3" do
    test "creates a reaction with default slide 0", %{session: session} do
      assert {:ok, reaction} = Reactions.create_reaction(session, "❤️")
      assert reaction.emoji == "❤️"
      assert reaction.slide_number == 0
      assert reaction.talk_session_id == session.id
    end

    test "creates a reaction with a specified slide number", %{session: session} do
      assert {:ok, reaction} = Reactions.create_reaction(session, "😂", 5)
      assert reaction.slide_number == 5
    end

    test "requires emoji", %{session: session} do
      assert {:error, changeset} = Reactions.create_reaction(session, nil)
      assert "can't be blank" in errors_on(changeset).emoji
    end
  end

  describe "count_reactions/1" do
    test "returns count of reactions for a session", %{session: session} do
      Reactions.create_reaction(session, "❤️")
      Reactions.create_reaction(session, "😂")
      assert Reactions.count_reactions(session.id) == 2
    end

    test "returns 0 for a session with no reactions", %{session: session} do
      assert Reactions.count_reactions(session.id) == 0
    end
  end
end
