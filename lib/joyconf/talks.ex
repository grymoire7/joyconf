defmodule Joyconf.Talks do
  import Ecto.Query

  alias Joyconf.Repo
  alias Joyconf.Talks.Talk
  alias Joyconf.Talks.TalkSession

  def list_talks, do: Repo.all(Talk)

  def get_talk!(id), do: Repo.get!(Talk, id)

  def get_talk_by_slug(slug), do: Repo.get_by(Talk, slug: slug)

  def delete_talk(%Talk{} = talk), do: Repo.delete(talk)

  def create_talk(attrs) do
    %Talk{}
    |> Talk.changeset(attrs)
    |> Repo.insert()
  end

  def generate_slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end

  def start_session(%Talk{} = talk) do
    case get_active_session(talk.id) do
      nil ->
        n = count_sessions(talk.id)

        %TalkSession{talk_id: talk.id}
        |> TalkSession.changeset(%{
          label: "Session #{n + 1}",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  def stop_session(%TalkSession{} = session) do
    session
    |> TalkSession.changeset(%{ended_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def get_active_session(talk_id) do
    Repo.one(
      from s in TalkSession,
        where: s.talk_id == ^talk_id and is_nil(s.ended_at),
        limit: 1
    )
  end

  def get_session(id), do: Repo.get(TalkSession, id)
  def get_session!(id), do: Repo.get!(TalkSession, id)

  def list_sessions(talk_id) do
    from(s in TalkSession,
      where: s.talk_id == ^talk_id,
      left_join: r in assoc(s, :reactions),
      group_by: s.id,
      select: %{session: s, reaction_count: count(r.id)},
      order_by: [desc: s.started_at, desc: s.id]
    )
    |> Repo.all()
  end

  def rename_session(%TalkSession{} = session, label) when is_binary(label) do
    session
    |> TalkSession.changeset(%{label: label})
    |> Repo.update()
  end

  def delete_session(%TalkSession{} = session) do
    Repo.delete(session)
  end

  defp count_sessions(talk_id) do
    Repo.aggregate(from(s in TalkSession, where: s.talk_id == ^talk_id), :count)
  end
end
