defmodule Speechwave.Talks do
  import Ecto.Query

  alias Speechwave.Accounts.Scope
  alias Speechwave.Repo
  alias Speechwave.Talks.Talk
  alias Speechwave.Talks.TalkSession

  # ---------------------------------------------------------------------------
  # Talks — scope-aware (requires authenticated user)
  # ---------------------------------------------------------------------------

  def list_talks(%Scope{user: user}) do
    Repo.all(from t in Talk, where: t.user_id == ^user.id, order_by: [desc: t.inserted_at])
  end

  def get_talk!(%Scope{user: user}, id) do
    Repo.get_by!(Talk, id: id, user_id: user.id)
  end

  def create_talk(%Scope{user: user}, attrs) do
    %Talk{user_id: user.id}
    |> Talk.changeset(attrs)
    |> Repo.insert()
  end

  def delete_talk(%Talk{} = talk), do: Repo.delete(talk)

  # ---------------------------------------------------------------------------
  # Talks — public (no auth required, used by channel and audience views)
  # ---------------------------------------------------------------------------

  def get_talk_by_slug(slug), do: Repo.get_by(Talk, slug: slug)

  @doc "Returns talk with user preloaded. Used by ReactionChannel to check plan limits."
  def get_talk_with_owner(slug) do
    Repo.one(from t in Talk, where: t.slug == ^slug, preload: [:user])
  end

  # ---------------------------------------------------------------------------
  # Sessions
  # ---------------------------------------------------------------------------

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

  def stop_session(%TalkSession{ended_at: ended_at} = session) when not is_nil(ended_at) do
    {:ok, session}
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

  def delete_session(%TalkSession{} = session), do: Repo.delete(session)

  @doc """
  Counts completed sessions longer than 10 minutes (600 seconds) in the current
  calendar month for the scoped user across all their talks.
  Used to enforce the free tier `full_sessions_per_month` limit.
  """
  def count_full_sessions_this_month(%Scope{user: user}) do
    beginning_of_month =
      Date.utc_today()
      |> Date.beginning_of_month()
      |> DateTime.new!(~T[00:00:00])

    Repo.aggregate(
      from(s in TalkSession,
        join: t in Talk,
        on: t.id == s.talk_id and t.user_id == ^user.id,
        where: s.started_at >= ^beginning_of_month,
        where: not is_nil(s.ended_at),
        where: fragment("EXTRACT(EPOCH FROM (? - ?)) > 600", s.ended_at, s.started_at)
      ),
      :count
    )
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  def generate_slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end

  defp count_sessions(talk_id) do
    Repo.aggregate(from(s in TalkSession, where: s.talk_id == ^talk_id), :count)
  end
end
