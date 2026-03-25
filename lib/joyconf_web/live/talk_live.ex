defmodule JoyconfWeb.TalkLive do
  use JoyconfWeb, :live_view

  alias Joyconf.{Talks, RateLimiter}

  @emojis ["❤️", "😂", "🔥", "👏", "🤯"]

  def mount(%{"slug" => slug}, _session, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:ok, redirect(socket, to: "/")}

      talk ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Joyconf.PubSub, "reactions:#{slug}")
        end

        {:ok, assign(socket, talk: talk, emojis: @emojis, session_id: socket.id)}
    end
  end

  def handle_event("react", %{"emoji" => emoji}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id) do
      JoyconfWeb.Endpoint.broadcast!("reactions:#{socket.assigns.talk.slug}", "new_reaction", %{
        emoji: emoji
      })
    end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: emoji}},
        socket
      ) do
    {:noreply, push_event(socket, "new_reaction", %{emoji: emoji})}
  end
end
