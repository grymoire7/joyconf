defmodule SpeechwaveWeb.ReactionChannel do
  use Phoenix.Channel

  alias Speechwave.Plans
  alias Speechwave.Talks
  alias SpeechwaveWeb.Presence

  def join("reactions:" <> slug, _payload, socket) do
    case Talks.get_talk_with_owner(slug) do
      nil ->
        {:error, %{reason: "not_found"}}

      talk ->
        participant_count = Presence.list("reactions:#{slug}") |> map_size()

        case Plans.check(:max_participants, talk.user.plan, participant_count) do
          :ok ->
            send(self(), :after_join)
            {:ok, assign(socket, :talk, talk)}

          {:error, :limit_reached} ->
            {:error, %{reason: "capacity_reached"}}
        end
    end
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, "anon:#{inspect(self())}", %{
        joined_at: System.system_time(:second)
      })

    {:noreply, socket}
  end

  def handle_in("start_session", _payload, socket) do
    talk = socket.assigns.talk
    scope = %Speechwave.Accounts.Scope{user: talk.user}
    full_count = Talks.count_full_sessions_this_month(scope)

    case Plans.check(:full_sessions_per_month, talk.user.plan, full_count) do
      :ok ->
        case Talks.start_session(talk) do
          {:ok, session} ->
            {:reply, {:ok, %{session_id: session.id, label: session.label}}, socket}

          {:error, _changeset} ->
            {:reply, {:error, %{reason: "failed"}}, socket}
        end

      {:error, :limit_reached} ->
        {:reply, {:error, %{reason: "session_limit_reached"}}, socket}
    end
  end

  def handle_in("stop_session", %{"session_id" => session_id}, socket) do
    case Talks.get_session(session_id) do
      nil ->
        {:reply, {:error, %{reason: "not_found"}}, socket}

      %{ended_at: ended_at} when not is_nil(ended_at) ->
        {:reply, :ok, socket}

      %{talk_id: talk_id} = session when talk_id == socket.assigns.talk.id ->
        {:ok, _} = Talks.stop_session(session)
        {:reply, :ok, socket}

      _session ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("slide_changed", %{"slide" => slide}, socket)
      when is_integer(slide) and slide > 0 do
    SpeechwaveWeb.Endpoint.broadcast!(
      "slides:#{socket.assigns.talk.slug}",
      "slide_changed",
      %{slide: slide}
    )

    {:reply, :ok, socket}
  end

  def handle_in("slide_changed", _payload, socket) do
    {:reply, :ok, socket}
  end
end
