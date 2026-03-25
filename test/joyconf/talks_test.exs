defmodule Joyconf.TalksTest do
  use Joyconf.DataCase

  alias Joyconf.Talks
  alias Joyconf.Talks.Talk

  describe "Talk.changeset/2" do
    test "valid with title and slug" do
      cs = Talk.changeset(%Talk{}, %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
      assert cs.valid?
    end

    test "requires title" do
      cs = Talk.changeset(%Talk{}, %{slug: "test"})
      assert "can't be blank" in errors_on(cs).title
    end

    test "requires slug" do
      cs = Talk.changeset(%Talk{}, %{title: "Test"})
      assert "can't be blank" in errors_on(cs).slug
    end

    test "rejects slug with uppercase letters" do
      cs = Talk.changeset(%Talk{}, %{title: "Test", slug: "My-Slug"})
      assert "only lowercase letters, numbers, and hyphens" in errors_on(cs).slug
    end

    test "rejects slug with spaces" do
      cs = Talk.changeset(%Talk{}, %{title: "Test", slug: "test slug"})
      assert "only lowercase letters, numbers, and hyphens" in errors_on(cs).slug
    end

    test "rejects slug longer than 100 chars" do
      cs = Talk.changeset(%Talk{}, %{title: "Test", slug: String.duplicate("a", 101)})
      assert "should be at most 100 character(s)" in errors_on(cs).slug
    end
  end

  describe "create_talk/1" do
    test "creates a talk with valid attrs" do
      assert {:ok, talk} =
               Talks.create_talk(%{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})

      assert talk.title == "Elixir for Rubyists"
      assert talk.slug == "elixir-for-rubyists"
    end

    test "returns error on duplicate slug" do
      {:ok, _} = Talks.create_talk(%{title: "Talk 1", slug: "my-talk"})
      assert {:error, cs} = Talks.create_talk(%{title: "Talk 2", slug: "my-talk"})
      assert "has already been taken" in errors_on(cs).slug
    end
  end

  describe "get_talk_by_slug/1" do
    test "returns talk when found" do
      {:ok, talk} = Talks.create_talk(%{title: "Test", slug: "test-talk"})
      assert Talks.get_talk_by_slug("test-talk").id == talk.id
    end

    test "returns nil when not found" do
      assert Talks.get_talk_by_slug("nonexistent") == nil
    end
  end

  describe "list_talks/0" do
    test "returns all talks" do
      {:ok, _} = Talks.create_talk(%{title: "Talk A", slug: "talk-a"})
      {:ok, _} = Talks.create_talk(%{title: "Talk B", slug: "talk-b"})
      assert length(Talks.list_talks()) == 2
    end
  end

  describe "generate_slug/1" do
    test "lowercases and hyphenates words" do
      assert Talks.generate_slug("Elixir for Rubyists") == "elixir-for-rubyists"
    end

    test "removes special characters" do
      assert Talks.generate_slug("Hello, World!") == "hello-world"
    end

    test "collapses multiple spaces" do
      assert Talks.generate_slug("a  b") == "a-b"
    end
  end
end
