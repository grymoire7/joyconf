defmodule JoyconfWeb.ReactionChannel do
  use Phoenix.Channel

  alias Joyconf.Talks

  def join("reactions:" <> slug, _payload, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:error, %{reason: "not_found"}}

      talk ->
        {:ok, assign(socket, :talk, talk)}
    end
  end

  def handle_in("start_session", _payload, socket) do
    case Talks.start_session(socket.assigns.talk) do
      {:ok, session} ->
        {:reply, {:ok, %{session_id: session.id, label: session.label}}, socket}

      {:error, _changeset} ->
        {:reply, {:error, %{reason: "failed"}}, socket}
    end
  end

  # Guard against double-stop: if ended_at is already set, reply ok without
  # overwriting the original end timestamp.
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

  def handle_in("slide_changed", %{"slide" => slide}, socket) when is_integer(slide) and slide > 0 do
    JoyconfWeb.Endpoint.broadcast!(
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
