defmodule Speechwave.TalksFixtures do
  @moduledoc false
  # Test factory module. talk_fixture/2 and session_fixture/2 insert records
  # and return the structs, following the convention from phx.gen.auth's
  # AccountsFixtures. Import in test files with:
  #   import Speechwave.TalksFixtures
  alias Speechwave.Accounts.Scope

  def talk_fixture(user, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    {:ok, talk} =
      Speechwave.Talks.create_talk(
        %Scope{user: user},
        Enum.into(attrs, %{title: "Test Talk #{n}", slug: "test-talk-#{n}"})
      )

    talk
  end

  def session_fixture(talk, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
      talk_id: talk.id,
      label: Map.get(attrs, :label, "Session 1"),
      started_at: Map.get(attrs, :started_at, now),
      ended_at: Map.get(attrs, :ended_at, nil)
    })
  end
end
