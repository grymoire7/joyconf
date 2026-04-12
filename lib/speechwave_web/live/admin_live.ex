defmodule SpeechwaveWeb.AdminLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.Talks
  alias Speechwave.Talks.Talk

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       talks: Talks.list_talks(),
       form: to_form(Talk.changeset(%Talk{}, %{})),
       created_talk: nil,
       selected_talk: nil,
       selected_qr_data_uri: nil,
       sessions: [],
       renaming_session_id: nil,
       rename_form: nil
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
       selected_qr_data_uri: nil,
       sessions: [],
       renaming_session_id: nil,
       rename_form: nil
     )}
  end

  def handle_event("show_qr", %{"id" => id}, socket) do
    talk = Talks.get_talk!(String.to_integer(id))
    url = SpeechwaveWeb.Endpoint.url() <> "/t/#{talk.slug}"
    qr = Speechwave.QRCode.to_data_uri(url)
    sessions = Talks.list_sessions(talk.id)

    {:noreply,
     assign(socket,
       selected_talk: talk,
       selected_qr_data_uri: qr,
       sessions: sessions,
       renaming_session_id: nil,
       rename_form: nil
     )}
  end

  def handle_event("save", %{"talk" => attrs}, socket) do
    case Talks.create_talk(attrs) do
      {:ok, talk} ->
        url = SpeechwaveWeb.Endpoint.url() <> "/t/#{talk.slug}"
        qr = Speechwave.QRCode.to_data_uri(url)

        {:noreply,
         assign(socket,
           created_talk: talk,
           talks: Talks.list_talks(),
           form: to_form(Talk.changeset(%Talk{}, %{})),
           selected_talk: talk,
           selected_qr_data_uri: qr,
           sessions: [],
           renaming_session_id: nil,
           rename_form: nil
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("rename_session", %{"id" => id}, socket) do
    session = Talks.get_session!(String.to_integer(id))

    {:noreply,
     assign(socket,
       renaming_session_id: session.id,
       rename_form: to_form(%{"label" => session.label}, as: :rename)
     )}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, renaming_session_id: nil, rename_form: nil)}
  end

  def handle_event("save_rename", %{"rename" => %{"label" => label}}, socket) do
    session = Talks.get_session!(socket.assigns.renaming_session_id)

    case Talks.rename_session(session, label) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(renaming_session_id: nil, rename_form: nil)
         |> assign(sessions: Talks.list_sessions(socket.assigns.selected_talk.id))}

      {:error, changeset} ->
        {:noreply, assign(socket, rename_form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event("delete_session", %{"id" => id}, socket) do
    session = Talks.get_session!(String.to_integer(id))
    {:ok, _} = Talks.delete_session(session)

    {:noreply, assign(socket, sessions: Talks.list_sessions(socket.assigns.selected_talk.id))}
  end
end
