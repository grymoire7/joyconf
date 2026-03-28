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

  def slide_reaction_totals(session_id) do
    from(r in Reaction,
      where: r.talk_session_id == ^session_id,
      group_by: [r.slide_number, r.emoji],
      select: %{slide_number: r.slide_number, emoji: r.emoji, count: count(r.id)},
      order_by: [asc: r.slide_number]
    )
    |> Repo.all()
  end
end
