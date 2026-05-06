defmodule SpeechwaveWeb.UserLive.Settings do
  use SpeechwaveWeb, :live_view

  on_mount {SpeechwaveWeb.UserAuth, :require_sudo_mode}

  alias Speechwave.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your email and connected accounts</:subtitle>
        </.header>
      </div>

      <%!-- Email section --%>
      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <%!-- Connected OAuth accounts --%>
      <div id="connected-accounts" class="space-y-4">
        <h3 class="font-semibold text-base-content">Connected accounts</h3>
        <p class="text-sm text-base-content/70">
          Sign in faster using a linked account. Magic link is always available as a fallback.
        </p>

        <div class="space-y-2">
          <%= for provider <- ["google", "microsoft", "github"] do %>
            <% identity = Enum.find(@identities, &(&1.provider == provider)) %>
            <div
              id={"identity-#{provider}"}
              class="flex items-center justify-between p-3 rounded-lg border border-base-300"
            >
              <span class="font-medium capitalize">{provider}</span>
              <%= if identity do %>
                <button
                  id={"disconnect-#{provider}"}
                  phx-click="disconnect_identity"
                  phx-value-id={identity.id}
                  data-confirm={"Disconnect your #{provider} account?"}
                  class="text-sm text-error hover:underline"
                >
                  Disconnect
                </button>
              <% else %>
                <.link
                  id={"connect-#{provider}"}
                  href={~p"/auth/#{provider}"}
                  class="text-sm text-primary hover:underline"
                >
                  Connect
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <div class="divider" />

      <%!-- API Key section --%>
      <div class="space-y-2">
        <h3 class="font-semibold text-base-content">Browser Extension API Key</h3>
        <p class="text-sm text-base-content/70">
          Paste this key into the Speechwave browser extension to authenticate.
          Keep it secret.
        </p>
        <div class="flex gap-2 items-center">
          <input
            id="api-key-display"
            type="text"
            readonly
            value={@api_key}
            class="flex-1 font-mono text-sm px-3 py-2 rounded-lg border border-base-300 bg-base-200 text-base-content"
            phx-hook=".SelectOnClick"
          />
          <button
            id="regenerate-api-key-btn"
            phx-click="regenerate_api_key"
            data-confirm="Regenerate your API key? Any active extension connections will be disconnected immediately."
            class="px-4 py-2 text-sm font-medium rounded-lg border border-base-300 hover:bg-base-200 transition-colors"
          >
            Regenerate
          </button>
        </div>
      </div>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SelectOnClick">
      export default {
        mounted() { this.el.addEventListener("click", () => this.el.select()) }
      }
    </script>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:api_key, user.api_key)
      |> assign(:identities, Accounts.list_user_identities(user))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("disconnect_identity", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    identity = Enum.find(socket.assigns.identities, &(to_string(&1.id) == id))

    if identity && identity.user_id == user.id do
      {:ok, _} = Accounts.delete_user_identity(identity)
      {:noreply, assign(socket, :identities, Accounts.list_user_identities(user))}
    else
      {:noreply, put_flash(socket, :error, "Could not disconnect that account.")}
    end
  end

  def handle_event("regenerate_api_key", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, updated_user} = Accounts.regenerate_api_key(user)

    SpeechwaveWeb.Endpoint.broadcast!("user:#{user.id}:disconnect", "disconnect", %{})

    {:noreply, assign(socket, :api_key, updated_user.api_key)}
  end
end
