defmodule SpeechwaveWeb.UserLive.Login do
  use SpeechwaveWeb, :live_view

  alias Speechwave.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-6">
        <div class="text-center">
          <.header>
            Sign in to Speechwave
            <:subtitle>Enter your email to receive a sign-in link</:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>Running the local mail adapter.</p>
            <p>
              Sign-in links appear at <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <%= if @link_sent do %>
          <div id="magic-link-sent" class="text-center space-y-2">
            <p class="font-medium">Check your inbox</p>
            <p class="text-sm text-base-content/70">
              We sent a sign-in link to <strong>{@submitted_email}</strong>.
              It expires in 15 minutes.
            </p>
            <.link navigate={~p"/users/log-in"} class="text-sm underline">
              Try a different email
            </.link>
          </div>
        <% else %>
          <.form
            for={@form}
            id="magic-link-form"
            phx-submit="submit_magic"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full" phx-disable-with="Sending…">
              Send sign-in link <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <div class="divider text-sm">or continue with</div>

          <div id="oauth-buttons" class="flex flex-col gap-3">
            <.link
              :if={oauth_provider_configured?(:google)}
              href={~p"/auth/google"}
              class="btn btn-outline w-full"
            >
              <.icon name="hero-globe-alt" class="size-5" /> Google
            </.link>
            <.link
              :if={oauth_provider_configured?(:microsoft)}
              href={~p"/auth/microsoft"}
              class="btn btn-outline w-full"
            >
              <.icon name="hero-building-office" class="size-5" /> Microsoft
            </.link>
            <.link
              :if={oauth_provider_configured?(:github)}
              href={~p"/auth/github"}
              class="btn btn-outline w-full"
            >
              <.icon name="hero-code-bracket" class="size-5" /> GitHub
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: "user")
    {:ok, assign(socket, form: form, link_sent: false, submitted_email: nil)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case Accounts.register_or_get_user_by_email(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/magic_link/#{&1}"))

      {:error, _} ->
        nil
    end

    {:noreply, assign(socket, link_sent: true, submitted_email: email)}
  end

  defp local_mail_adapter? do
    Application.get_env(:speechwave, Speechwave.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  defp oauth_provider_configured?(provider) do
    providers = Application.get_env(:speechwave, :oauth_providers, [])
    Keyword.has_key?(providers, provider) && providers[provider] != nil
  end
end
