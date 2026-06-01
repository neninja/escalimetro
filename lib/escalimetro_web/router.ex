defmodule EscalimetroWeb.Router do
  use EscalimetroWeb, :router

  import EscalimetroWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EscalimetroWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", EscalimetroWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:escalimetro, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EscalimetroWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", EscalimetroWeb do
    pipe_through [:browser, :require_authenticated_user, :require_confirmed_user]

    live_session :require_authenticated_user,
      on_mount: [
        {EscalimetroWeb.UserAuth, :require_authenticated},
        {EscalimetroWeb.UserAuth, :require_confirmed}
      ] do
      live "/events", EventLive.Index, :index
      live "/events/new", EventLive.Form, :new
      live "/events/:id", EventLive.Show, :show
      live "/events/:id/edit", EventLive.Form, :edit
      live "/events/:event_id/ballots/new", BallotLive.Form, :new
      live "/events/:event_id/ballots/:id/edit", BallotLive.Form, :edit
      live "/events/:event_id/participants", ParticipantLive.Index, :index
      live "/events/:event_id/moderation", ModerationLive.Index, :index
      live "/events/:event_id/results", ResultsLive.Show, :show
      live "/events/:event_id/invite", InviteLive.Admin, :show
      live "/backoffice", BackofficeLive.Dashboard, :index

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/backoffice/users/:id/impersonate", Backoffice.UserImpersonationController, :create
    delete "/backoffice/impersonation", Backoffice.UserImpersonationController, :delete

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", EscalimetroWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{EscalimetroWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive, :show
      live "/join/:token", InviteLive.Join, :show
      live "/events/public/:participant_token", ParticipantLive.Event, :show
      live "/results/:token", ResultsLive.Show, :public

      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
