defmodule Web.Router do
  use Web, :router

  import Web.AccountAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_account
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :maybe_authenticated do
    plug Web.Plugs.RedirectIfAuthenticated
  end

  @sandbox_hooks if(Application.compile_env(:ancestry, :sql_sandbox),
                   do: [Web.LiveAcceptance],
                   else: []
                 )

  scope "/", Web do
    pipe_through [:browser, :maybe_authenticated]

    get "/", PageController, :landing
  end

  scope "/", Web do
    pipe_through [:browser, :require_authenticated_account]

    live_session :default,
      on_mount: @sandbox_hooks ++ [{Web.AccountAuth, :require_authenticated}] do
      live "/org", OrganizationLive.Index, :index
    end

    live_session :admin,
      on_mount:
        @sandbox_hooks ++
          [
            {Web.AccountAuth, :require_authenticated},
            Permit.Phoenix.LiveView.AuthorizeHook
          ] do
      live "/admin/accounts", AccountManagementLive.Index, :index
      live "/admin/accounts/new", AccountManagementLive.New, :new
      live "/admin/accounts/:id", AccountManagementLive.Show, :show
      live "/admin/accounts/:id/edit", AccountManagementLive.Edit, :edit
    end

    scope "/org/:org_id" do
      live_session :organization,
        on_mount:
          @sandbox_hooks ++
            [{Web.AccountAuth, :require_authenticated}, Web.EnsureOrganization] do
        live "/", FamilyLive.Index, :index
        live "/families/new", FamilyLive.New, :new
        live "/families/:family_id", FamilyLive.Show, :show
        live "/families/:family_id/galleries/:id", GalleryLive.Show, :show
        live "/families/:family_id/vaults/:vault_id", VaultLive.Show, :show
        live "/families/:family_id/vaults/:vault_id/memories/new", MemoryLive.Form, :new
        live "/families/:family_id/vaults/:vault_id/memories/:memory_id", MemoryLive.Show, :show

        live "/families/:family_id/vaults/:vault_id/memories/:memory_id/edit",
             MemoryLive.Form,
             :edit

        live "/families/:family_id/members/new", PersonLive.New, :new
        live "/people/:id", PersonLive.Show, :show
        live "/families/:family_id/kinship", KinshipLive, :index
        live "/families/:family_id/people", PeopleLive.Index, :index
        live "/people", OrgPeopleLive.Index, :index
      end
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

  ## Test-only routes (available when sql_sandbox is enabled)
  if Application.compile_env(:ancestry, :sql_sandbox) do
    scope "/test", Web do
      pipe_through :browser
      get "/session/:account_id", TestSessionController, :create
    end
  end

  ## Authentication routes

  scope "/", Web do
    pipe_through [:browser, :require_authenticated_account]

    live_session :require_authenticated_account,
      on_mount: [{Web.AccountAuth, :require_authenticated}] do
      live "/accounts/settings", AccountLive.Settings, :edit
      live "/accounts/settings/confirm-email/:token", AccountLive.Settings, :confirm_email
    end

    post "/accounts/update-password", AccountSessionController, :update_password
  end

  scope "/", Web do
    pipe_through [:browser]

    live_session :current_account,
      on_mount: [{Web.AccountAuth, :mount_current_scope}] do
      # Registration temporarily disabled — uncomment when ready
      # live "/accounts/register", AccountLive.Registration, :new
      live "/accounts/log-in", AccountLive.Login, :new
      live "/accounts/log-in/:token", AccountLive.Confirmation, :new
    end

    post "/accounts/log-in", AccountSessionController, :create
    delete "/accounts/log-out", AccountSessionController, :delete
  end
end
