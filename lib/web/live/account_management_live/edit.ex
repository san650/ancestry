defmodule Web.AccountManagementLive.Edit do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account,
    scope_subject: &Function.identity/1,
    skip_preload: [:index, :new, :show, :edit]

  alias Ancestry.Identity
  alias Ancestry.Identity.Account
  alias Ancestry.Identity.AccountToken
  alias Ancestry.Organizations

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account = Identity.get_account_with_orgs!(id)
    changeset = Account.admin_changeset(account, %{}, mode: :edit)
    organizations = Organizations.list_organizations()
    selected_org_ids = Enum.map(account.organizations, & &1.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "account:#{id}")
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Edit Account"))
     |> assign(:account, account)
     |> assign(:form, to_form(changeset))
     |> assign(:organizations, organizations)
     |> assign(:selected_org_ids, selected_org_ids)
     |> assign(:confirm_deactivate, false)
     |> assign(:confirm_reactivate, false)
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"account" => account_params} = params, socket) do
    changeset =
      socket.assigns.account
      |> Account.admin_changeset(account_params, mode: :edit)
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
    account = socket.assigns.account
    current_account = socket.assigns.current_scope.account
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

    case Identity.update_admin_account(account, account_params, current_account) do
      {:ok, updated_account} ->
        Identity.update_account_organizations(updated_account, org_ids)

        if avatar_original_path do
          Identity.update_avatar_status(updated_account, "pending")

          %{account_id: updated_account.id, original_path: avatar_original_path}
          |> Ancestry.Workers.ProcessAccountAvatarJob.new()
          |> Oban.insert()
        end

        password = account_params["password"]

        if is_binary(password) and password != "" do
          import Ecto.Query
          tokens = Ancestry.Repo.all(from(t in AccountToken, where: t.account_id == ^account.id))
          Ancestry.Repo.delete_all(from(t in AccountToken, where: t.account_id == ^account.id))
          Web.AccountAuth.disconnect_sessions(tokens)
        end

        {:noreply,
         socket
         |> put_flash(:info, gettext("Account updated successfully."))
         |> push_navigate(to: ~p"/admin/accounts/#{updated_account.id}")}

      {:error, :cannot_change_own_role} ->
        {:noreply, put_flash(socket, :error, gettext("You cannot change your own role."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  # Deactivate/Reactivate handlers (same pattern as Show)
  def handle_event("request_deactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_deactivate, true)}
  end

  def handle_event("cancel_deactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_deactivate, false)}
  end

  def handle_event("confirm_deactivate", _params, socket) do
    current_account = socket.assigns.current_scope.account
    account = socket.assigns.account

    case Identity.deactivate_account(account, current_account) do
      {:ok, _account} ->
        account = Identity.get_account_with_orgs!(account.id)

        {:noreply,
         socket
         |> assign(:account, account)
         |> assign(:confirm_deactivate, false)
         |> put_flash(:info, gettext("Account deactivated successfully."))}

      {:error, :cannot_deactivate_self} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, gettext("You cannot deactivate your own account."))}

      {:error, :last_admin} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, gettext("Cannot deactivate the last admin account."))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, gettext("Failed to deactivate account."))}
    end
  end

  def handle_event("request_reactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_reactivate, true)}
  end

  def handle_event("cancel_reactivate", _params, socket) do
    {:noreply, assign(socket, :confirm_reactivate, false)}
  end

  def handle_event("confirm_reactivate", _params, socket) do
    account = socket.assigns.account

    case Identity.reactivate_account(account) do
      {:ok, _account} ->
        account = Identity.get_account_with_orgs!(account.id)

        {:noreply,
         socket
         |> assign(:account, account)
         |> assign(:confirm_reactivate, false)
         |> put_flash(:info, gettext("Account reactivated successfully."))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirm_reactivate, false)
         |> put_flash(:error, gettext("Failed to reactivate account."))}
    end
  end

  @impl true
  def handle_info({:avatar_processed, account}, socket) do
    {:noreply, assign(socket, :account, account)}
  end

  def handle_info({:avatar_failed, _account}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Avatar processing failed."))}
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
            class="p-2 -ml-2 text-cm-text-muted hover:text-cm-black lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
            aria-label={gettext("Open menu")}
            {test_id("hamburger-menu")}
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <.link
            navigate={~p"/admin/accounts/#{@account.id}"}
            class="hidden lg:flex text-cm-text-muted hover:text-cm-black transition-colors"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-lg font-cm-display font-bold text-cm-black">
            {gettext("Edit Account")}
          </h1>
        </div>
      </:toolbar>

      <.nav_drawer current_scope={@current_scope}>
        <.link
          href={~p"/org"}
          {test_id("nav-organizations")}
          class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-cm min-h-[44px] text-cm-black hover:bg-cm-surface transition-colors"
        >
          <.icon name="hero-building-office-2" class="size-5 shrink-0 text-cm-text-muted" />
          <span class="font-cm-body text-sm">{gettext("Organizations")}</span>
        </.link>
        <.link
          href={~p"/admin/accounts"}
          {test_id("nav-accounts")}
          class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-cm min-h-[44px] text-cm-black hover:bg-cm-surface transition-colors"
        >
          <.icon name="hero-users" class="size-5 shrink-0 text-cm-text-muted" />
          <span class="font-cm-body text-sm">{gettext("Accounts")}</span>
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
          <.input field={@form[:name]} type="text" label={gettext("Full name")} />
          <.input field={@form[:email]} type="email" label={gettext("Email")} required />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("New password")}
            placeholder={gettext("Leave blank to keep current")}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            placeholder={gettext("Leave blank to keep current")}
          />
          <.input
            field={@form[:role]}
            type="select"
            label={gettext("Role")}
            options={[
              {gettext("Viewer"), :viewer},
              {gettext("Editor"), :editor},
              {gettext("Admin"), :admin}
            ]}
            disabled={@account.id == @current_scope.account.id}
          />
          <.input
            field={@form[:locale]}
            type="select"
            label={gettext("Language")}
            options={[{"English", "en-US"}, {"Español", "es-UY"}]}
          />

          <%!-- Avatar upload --%>
          <div>
            <label class="block text-sm font-medium text-cm-black mb-2">
              {gettext("Avatar")}
            </label>
            <.live_file_input upload={@uploads.avatar} class="text-sm" {test_id("avatar-upload")} />
            <div :for={entry <- @uploads.avatar.entries} class="mt-2">
              <.live_img_preview entry={entry} class="w-20 h-20 rounded-full object-cover" />
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="text-cm-error text-xs mt-1 hover:underline"
              >
                {gettext("Remove")}
              </button>
              <p
                :for={err <- upload_errors(@uploads.avatar, entry)}
                class="text-cm-error text-xs mt-1"
              >
                {error_to_string(err)}
              </p>
            </div>
          </div>

          <%!-- Organization selection --%>
          <div>
            <label class="block text-sm font-medium text-cm-black mb-2">
              {gettext("Organizations")}
            </label>
            <div class="space-y-2" {test_id("org-selection")}>
              <label :for={org <- @organizations} class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  name="organization_ids[]"
                  value={org.id}
                  checked={org.id in @selected_org_ids}
                  class="rounded border-cm-border"
                  {test_id("org-checkbox-#{org.id}")}
                />
                <span class="text-sm text-cm-black">{org.name}</span>
              </label>
            </div>
          </div>

          <div class="flex gap-4">
            <button
              type="submit"
              class="rounded-cm bg-cm-indigo px-6 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-indigo/90 transition-colors"
              {test_id("account-submit-btn")}
            >
              {gettext("Save Changes")}
            </button>
            <.link
              navigate={~p"/admin/accounts/#{@account.id}"}
              class="rounded-cm px-6 py-2 text-sm font-cm-body text-cm-text-muted hover:text-cm-black transition-colors"
            >
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>

        <%!-- Deactivate/Reactivate section (hidden for own account) --%>
        <%= if @account.id != @current_scope.account.id do %>
          <div class="mt-8 pt-6 border-t border-cm-border/20">
            <%= if is_nil(@account.deactivated_at) do %>
              <button
                phx-click="request_deactivate"
                class="rounded-cm bg-cm-error px-4 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-error/90 transition-colors"
                {test_id("account-deactivate-btn")}
              >
                {gettext("Deactivate Account")}
              </button>
            <% else %>
              <button
                phx-click="request_reactivate"
                class="rounded-cm bg-cm-indigo px-4 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-indigo/90 transition-colors"
                {test_id("account-reactivate-btn")}
              >
                {gettext("Reactivate Account")}
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @confirm_deactivate do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
          {test_id("deactivate-modal")}
        >
          <div class="bg-cm-white rounded-cm p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-cm-display font-bold text-cm-black mb-2">
              {gettext("Deactivate Account")}
            </h3>
            <p class="text-sm text-cm-text-muted mb-6">
              {gettext(
                "Are you sure you want to deactivate %{email}? They will be immediately logged out and unable to log in.",
                email: @account.email
              )}
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_deactivate"
                class="rounded-cm px-4 py-2 text-sm font-cm-body font-medium text-cm-text-muted hover:text-cm-black transition-colors"
                {test_id("deactivate-cancel-btn")}
              >
                {gettext("Cancel")}
              </button>
              <button
                phx-click="confirm_deactivate"
                class="rounded-cm bg-cm-error px-4 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-error/90 transition-colors"
                {test_id("deactivate-confirm-btn")}
              >
                {gettext("Deactivate")}
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @confirm_reactivate do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
          {test_id("reactivate-modal")}
        >
          <div class="bg-cm-white rounded-cm p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-cm-display font-bold text-cm-black mb-2">
              {gettext("Reactivate Account")}
            </h3>
            <p class="text-sm text-cm-text-muted mb-6">
              {gettext(
                "Are you sure you want to reactivate %{email}? They will be able to log in again.",
                email: @account.email
              )}
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_reactivate"
                class="rounded-cm px-4 py-2 text-sm font-cm-body font-medium text-cm-text-muted hover:text-cm-black transition-colors"
                {test_id("reactivate-cancel-btn")}
              >
                {gettext("Cancel")}
              </button>
              <button
                phx-click="confirm_reactivate"
                class="rounded-cm bg-cm-indigo px-4 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-indigo/90 transition-colors"
                {test_id("reactivate-confirm-btn")}
              >
                {gettext("Reactivate")}
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp error_to_string(:too_large), do: gettext("File is too large (max 10MB)")
  defp error_to_string(:too_many_files), do: gettext("Only one avatar allowed")
  defp error_to_string(:not_accepted), do: gettext("Invalid file type")
  defp error_to_string(err), do: inspect(err)
end
