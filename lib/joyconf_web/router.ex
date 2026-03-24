defmodule JoyconfWeb.Router do
  use JoyconfWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JoyconfWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin do
    plug JoyconfWeb.AdminAuth
  end

  scope "/", JoyconfWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/admin", JoyconfWeb do
    pipe_through [:browser, :admin]
    live "/", AdminLive, :index
    live "/talks/new", AdminLive, :new
  end

  scope "/t", JoyconfWeb do
    pipe_through :browser
    live "/:slug", TalkLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", JoyconfWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:joyconf, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JoyconfWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
