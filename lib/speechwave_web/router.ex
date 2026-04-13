defmodule SpeechwaveWeb.Router do
  use SpeechwaveWeb, :router

  import SpeechwaveWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SpeechwaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ---------------------------------------------------------------------------
  # Public routes — no auth required
  # ---------------------------------------------------------------------------

  scope "/", SpeechwaveWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/t/:slug", TalkLive
  end

  # ---------------------------------------------------------------------------
  # Authenticated routes — require login
  # ---------------------------------------------------------------------------

  scope "/", SpeechwaveWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SpeechwaveWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive
      live "/sessions/:id", SessionAnalyticsLive, :show
      live "/sessions/:id/compare/:other_id", SessionAnalyticsLive, :compare
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  # ---------------------------------------------------------------------------
  # Auth routes (login, register, confirm — no auth required)
  # ---------------------------------------------------------------------------

  scope "/", SpeechwaveWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:speechwave, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SpeechwaveWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
