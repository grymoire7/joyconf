defmodule Joyconf.Reactions do
  import Ecto.Query

  alias Joyconf.Repo
  alias Joyconf.Reactions.Reaction
  alias Joyconf.Talks.TalkSession

  def create_reaction(%TalkSession{} = session, emoji, slide_number \\ 0) do
    %Reaction{talk_session_id: session.id}
    |> Reaction.changeset(%{emoji: emoji, slide_number: slide_number})
    |> Repo.insert()
  end

  def count_reactions(session_id) do
    Repo.aggregate(from(r in Reaction, where: r.talk_session_id == ^session_id), :count)
  end
end
