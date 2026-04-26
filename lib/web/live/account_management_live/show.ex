defmodule Web.AccountManagementLive.Show do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account,
    scope_subject: &Function.identity/1,
    skip_preload: [:index, :new, :show, :edit]

  alias Ancestry.Identity

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

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "account:#{id}")
    end

    {:ok,
     socket
     |> assign(:page_title, account.email)
     |> assign(:account, account)
     |> assign(:confirm_deactivate, false)
     |> assign(:confirm_reactivate, false)}
  end

  @impl true
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
        <div class="max-w-7xl mx-auto flex items-center justify-between px-4 sm:px-6 lg:px-8 py-3">
          <div class="flex items-center gap-3">
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
              navigate={~p"/admin/accounts"}
              class="hidden lg:flex text-cm-text-muted hover:text-cm-black transition-colors"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <h1 class="text-lg font-cm-display font-bold text-cm-indigo uppercase tracking-wider">
              {gettext("Account Details")}
            </h1>
          </div>
          <.link
            navigate={~p"/admin/accounts/#{@account.id}/edit"}
            class="inline-flex items-center gap-2 rounded-cm bg-cm-coral px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-white hover:bg-cm-coral-hover transition-colors"
            {test_id("account-edit-btn")}
          >
            <.icon name="hero-pencil-square" class="size-4" /> {gettext("Edit")}
          </.link>
        </div>
      </:toolbar>

      <.nav_drawer current_scope={@current_scope} />

      <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="bg-cm-white rounded-cm p-6 border-2 border-cm-black" {test_id("account-detail")}>
          <dl class="space-y-4">
            <div>
              <dt class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
                {gettext("Email")}
              </dt>
              <dd class="mt-1 text-sm text-cm-black" {test_id("account-email")}>
                {@account.email}
              </dd>
            </div>

            <div>
              <dt class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
                {gettext("Name")}
              </dt>
              <dd class="mt-1 text-sm text-cm-black" {test_id("account-name")}>
                {@account.name || "—"}
              </dd>
            </div>

            <div>
              <dt class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
                {gettext("Role")}
              </dt>
              <dd class="mt-1 text-sm text-cm-black" {test_id("account-role")}>
                {String.capitalize(to_string(@account.role))}
              </dd>
            </div>

            <div>
              <dt class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
                {gettext("Status")}
              </dt>
              <dd class="mt-1" {test_id("account-status")}>
                <%= if @account.deactivated_at do %>
                  <span class="text-cm-error text-sm font-medium">{gettext("Deactivated")}</span>
                <% else %>
                  <span class="text-cm-indigo text-sm font-medium">{gettext("Active")}</span>
                <% end %>
              </dd>
            </div>

            <div>
              <dt class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
                {gettext("Organizations")}
              </dt>
              <dd class="mt-1 flex flex-wrap gap-1" {test_id("account-organizations")}>
                <%= if @account.organizations == [] do %>
                  <span class="text-sm text-cm-text-muted">{gettext("None")}</span>
                <% else %>
                  <span
                    :for={org <- @account.organizations}
                    class="inline-block bg-cm-surface rounded-cm px-2 py-0.5 font-cm-mono text-[10px] uppercase tracking-wider"
                  >
                    {org.name}
                  </span>
                <% end %>
              </dd>
            </div>

            <%= if @account.deactivated_at do %>
              <div>
                <dt class="font-cm-mono text-[10px] font-bold text-cm-text-muted uppercase tracking-wider">
                  {gettext("Deactivated By")}
                </dt>
                <dd
                  class="mt-1 text-sm text-cm-text-muted"
                  {test_id("account-deactivated-by")}
                >
                  <%= if @account.deactivator do %>
                    {@account.deactivator.email}
                  <% else %>
                    {gettext("Unknown")}
                  <% end %>
                </dd>
              </div>
            <% end %>
          </dl>

          <div class="mt-6 pt-6 border-t-2 border-cm-black flex gap-3">
            <%= if is_nil(@account.deactivated_at) and @account.id != @current_scope.account.id do %>
              <button
                phx-click="request_deactivate"
                class="rounded-cm bg-cm-error px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-white hover:bg-cm-error/90 transition-colors"
                {test_id("account-deactivate-btn")}
              >
                {gettext("Deactivate")}
              </button>
            <% end %>

            <%= if @account.deactivated_at && @account.id != @current_scope.account.id do %>
              <button
                phx-click="request_reactivate"
                class="rounded-cm bg-cm-indigo px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-white hover:bg-cm-indigo/90 transition-colors"
                {test_id("account-reactivate-btn")}
              >
                {gettext("Reactivate")}
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @confirm_deactivate do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
          {test_id("deactivate-modal")}
        >
          <div class="bg-cm-white rounded-cm p-6 max-w-sm mx-4 border-2 border-cm-black">
            <h3 class="text-lg font-cm-display font-bold text-cm-indigo uppercase tracking-wider mb-2">
              {gettext("Deactivate Account")}
            </h3>
            <p class="text-sm text-cm-text-muted mb-6 font-cm-body">
              {gettext(
                "Are you sure you want to deactivate %{email}? They will be immediately logged out and unable to log in.",
                email: @account.email
              )}
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_deactivate"
                class="rounded-cm px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider border-2 border-cm-black text-cm-black hover:bg-cm-surface transition-colors"
                {test_id("deactivate-cancel-btn")}
              >
                {gettext("Cancel")}
              </button>
              <button
                phx-click="confirm_deactivate"
                class="rounded-cm bg-cm-error px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-white hover:bg-cm-error/90 transition-colors"
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
          <div class="bg-cm-white rounded-cm p-6 max-w-sm mx-4 border-2 border-cm-black">
            <h3 class="text-lg font-cm-display font-bold text-cm-indigo uppercase tracking-wider mb-2">
              {gettext("Reactivate Account")}
            </h3>
            <p class="text-sm text-cm-text-muted mb-6 font-cm-body">
              {gettext(
                "Are you sure you want to reactivate %{email}? They will be able to log in again.",
                email: @account.email
              )}
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_reactivate"
                class="rounded-cm px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider border-2 border-cm-black text-cm-black hover:bg-cm-surface transition-colors"
                {test_id("reactivate-cancel-btn")}
              >
                {gettext("Cancel")}
              </button>
              <button
                phx-click="confirm_reactivate"
                class="rounded-cm bg-cm-indigo px-4 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-white hover:bg-cm-indigo/90 transition-colors"
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
end
