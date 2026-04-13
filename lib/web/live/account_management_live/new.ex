defmodule Web.AccountManagementLive.New do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account,
    scope_subject: &Function.identity/1,
    skip_preload: [:index, :new, :show, :edit]

  alias Ancestry.Identity
  alias Ancestry.Identity.Account
  alias Ancestry.Organizations

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, "You don't have permission to access this page")
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(_params, _session, socket) do
    changeset = Account.admin_changeset(%Account{}, %{})
    organizations = Organizations.list_organizations()

    {:ok,
     socket
     |> assign(:page_title, "New Account")
     |> assign(:form, to_form(changeset))
     |> assign(:organizations, organizations)
     |> assign(:selected_org_ids, [])
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"account" => account_params} = params, socket) do
    changeset =
      %Account{}
      |> Account.admin_changeset(account_params)
      |> Map.put(:action, :validate)

    selected_org_ids =
      (params["organization_ids"] || [])
      |> Enum.map(&String.to_integer/1)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:selected_org_ids, selected_org_ids)}
  end

  def handle_event("save", %{"account" => account_params} = params, socket) do
    org_ids = params["organization_ids"] || []

    avatar_original_path =
      consume_uploaded_entries(socket, :avatar, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_key = Path.join(["uploads", "originals", uuid, "avatar#{ext}"])
        original_path = Ancestry.Storage.store_original(tmp_path, dest_key)
        {:ok, original_path}
      end)
      |> List.first()

    case Identity.create_admin_account(account_params, org_ids) do
      {:ok, account} ->
        if avatar_original_path do
          Identity.update_avatar_status(account, "pending")

          %{account_id: account.id, original_path: avatar_original_path}
          |> Ancestry.Workers.ProcessAccountAvatarJob.new()
          |> Oban.insert()
        end

        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully")
         |> push_navigate(to: ~p"/admin/accounts")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center gap-4 px-4 sm:px-6 lg:px-8 py-3">
          <button
            type="button"
            phx-click={toggle_nav_drawer()}
            class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
            aria-label="Open menu"
            {test_id("hamburger-menu")}
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <.link
            navigate={~p"/admin/accounts"}
            class="hidden lg:flex text-ds-on-surface-variant hover:text-ds-on-surface"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">New Account</h1>
        </div>
      </:toolbar>

      <.nav_drawer current_scope={@current_scope}>
        <.link
          href={~p"/org"}
          {test_id("nav-organizations")}
          class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
        >
          <.icon name="hero-building-office-2" class="size-5 shrink-0 text-ds-on-surface-variant" />
          <span class="font-ds-body text-sm">Organizations</span>
        </.link>
        <.link
          href={~p"/admin/accounts"}
          {test_id("nav-accounts")}
          class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
        >
          <.icon name="hero-users" class="size-5 shrink-0 text-ds-on-surface-variant" />
          <span class="font-ds-body text-sm">Accounts</span>
        </.link>
      </.nav_drawer>

      <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <.form
          for={@form}
          id="account-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
          {test_id("account-form")}
        >
          <.input field={@form[:name]} type="text" label="Full name" />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:password]} type="password" label="Password" required />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
          />
          <.input
            field={@form[:role]}
            type="select"
            label="Role"
            options={[{"Viewer", :viewer}, {"Editor", :editor}, {"Admin", :admin}]}
          />
          <.input
            field={@form[:locale]}
            type="select"
            label={gettext("Language")}
            options={[{"English", "en-US"}, {"Español", "es-UY"}]}
          />

          <%!-- Avatar upload --%>
          <div>
            <label class="block text-sm font-medium text-ds-on-surface mb-2">Avatar</label>
            <.live_file_input upload={@uploads.avatar} class="text-sm" {test_id("avatar-upload")} />
            <div :for={entry <- @uploads.avatar.entries} class="mt-2">
              <.live_img_preview entry={entry} class="w-20 h-20 rounded-full object-cover" />
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-ds-error text-xs mt-1 hover:underline"
              >
                Remove
              </button>
              <p
                :for={err <- upload_errors(@uploads.avatar, entry)}
                class="text-ds-error text-xs mt-1"
              >
                {error_to_string(err)}
              </p>
            </div>
          </div>

          <%!-- Organization selection --%>
          <div>
            <label class="block text-sm font-medium text-ds-on-surface mb-2">Organizations</label>
            <div class="space-y-2" {test_id("org-selection")}>
              <label :for={org <- @organizations} class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name="organization_ids[]"
                  value={org.id}
                  checked={org.id in @selected_org_ids}
                  class="rounded border-ds-outline"
                  {test_id("org-checkbox-#{org.id}")}
                />
                <span class="text-sm text-ds-on-surface">{org.name}</span>
              </label>
            </div>
          </div>

          <div class="flex gap-4">
            <button
              type="submit"
              class="rounded-ds-sharp bg-ds-primary px-6 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
              {test_id("account-submit-btn")}
            >
              Create Account
            </button>
            <.link
              navigate={~p"/admin/accounts"}
              class="rounded-ds-sharp px-6 py-2 text-sm font-ds-body text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Only one avatar allowed"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(err), do: inspect(err)
end
