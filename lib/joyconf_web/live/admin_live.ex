defmodule JoyconfWeb.AdminLive do
  use JoyconfWeb, :live_view

  alias Joyconf.Talks
  alias Joyconf.Talks.Talk

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       talks: Talks.list_talks(),
       form: to_form(Talk.changeset(%Talk{}, %{})),
       created_talk: nil,
       selected_talk: nil,
       selected_qr_data_uri: nil
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_event("validate", %{"talk" => attrs}, socket) do
    slug =
      if attrs["title"] != "" and attrs["slug"] == "" do
        Talks.generate_slug(attrs["title"])
      else
        attrs["slug"]
      end

    changeset = Talk.changeset(%Talk{}, Map.put(attrs, "slug", slug))
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("delete_talk", %{"id" => id}, socket) do
    talk = Talks.get_talk!(String.to_integer(id))
    {:ok, _} = Talks.delete_talk(talk)

    {:noreply,
     assign(socket,
       talks: Talks.list_talks(),
       selected_talk: nil,
       selected_qr_data_uri: nil
     )}
  end

  def handle_event("show_qr", %{"id" => id}, socket) do
    talk = Talks.get_talk!(String.to_integer(id))
    url = JoyconfWeb.Endpoint.url() <> "/t/#{talk.slug}"
    qr = Joyconf.QRCode.to_data_uri(url)

    {:noreply, assign(socket, selected_talk: talk, selected_qr_data_uri: qr)}
  end

  def handle_event("save", %{"talk" => attrs}, socket) do
    case Talks.create_talk(attrs) do
      {:ok, talk} ->
        url = JoyconfWeb.Endpoint.url() <> "/t/#{talk.slug}"
        qr = Joyconf.QRCode.to_data_uri(url)

        {:noreply,
         assign(socket,
           created_talk: talk,
           talks: Talks.list_talks(),
           form: to_form(Talk.changeset(%Talk{}, %{})),
           selected_talk: talk,
           selected_qr_data_uri: qr
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
