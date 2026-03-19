defmodule Web.Router do
  use Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Web do
    pipe_through :browser

    live_session :default do
      live "/", FamilyLive.Index, :index
      live "/families/new", FamilyLive.New, :new
      live "/families/:family_id", FamilyLive.Show, :show
      live "/families/:family_id/galleries/:id", GalleryLive.Show, :show

      live "/families/:family_id/members/new", PersonLive.New, :new
      live "/people/:id", PersonLive.Show, :show
      live "/families/:family_id/kinship", KinshipLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ancestry, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Web.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
