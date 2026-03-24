defmodule JoyconfWeb.ReactionChannel do
  use Phoenix.Channel

  alias Joyconf.Talks

  def join("reactions:" <> slug, _payload, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:error, %{reason: "not_found"}}

      talk ->
        Phoenix.PubSub.subscribe(Joyconf.PubSub, "reactions:#{slug}")
        {:ok, assign(socket, :talk, talk)}
    end
  end

  def handle_info({:reaction, emoji}, socket) do
    push(socket, "new_reaction", %{emoji: emoji})
    {:noreply, socket}
  end
end
