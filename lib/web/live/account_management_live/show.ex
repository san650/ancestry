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
     |> put_flash(:error, "You don't have permission to access this page")
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
         |> put_flash(:info, "Account deactivated successfully.")}

      {:error, :cannot_deactivate_self} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, "You cannot deactivate your own account.")}

      {:error, :last_admin} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, "Cannot deactivate the last admin account.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirm_deactivate, false)
         |> put_flash(:error, "Failed to deactivate account.")}
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
         |> put_flash(:info, "Account reactivated successfully.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:confirm_reactivate, false)
         |> put_flash(:error, "Failed to reactivate account.")}
    end
  end

  @impl true
  def handle_info({:avatar_processed, account}, socket) do
    {:noreply, assign(socket, :account, account)}
  end

  def handle_info({:avatar_failed, _account}, socket) do
    {:noreply, put_flash(socket, :error, "Avatar processing failed.")}
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
              class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
              aria-label="Open menu"
              {test_id("hamburger-menu")}
            >
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <.link
              navigate={~p"/admin/accounts"}
              class="hidden lg:flex text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">Account Details</h1>
          </div>
          <.link
            navigate={~p"/admin/accounts/#{@account.id}/edit"}
            class="inline-flex items-center gap-2 rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
            {test_id("account-edit-btn")}
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.link>
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

      <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="bg-ds-surface-card rounded-ds-sharp p-6 shadow-sm" {test_id("account-detail")}>
          <dl class="space-y-4">
            <div>
              <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wide">
                Email
              </dt>
              <dd class="mt-1 text-sm text-ds-on-surface" {test_id("account-email")}>
                {@account.email}
              </dd>
            </div>

            <div>
              <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wide">
                Name
              </dt>
              <dd class="mt-1 text-sm text-ds-on-surface" {test_id("account-name")}>
                {@account.name || "—"}
              </dd>
            </div>

            <div>
              <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wide">
                Role
              </dt>
              <dd class="mt-1 text-sm text-ds-on-surface" {test_id("account-role")}>
                {String.capitalize(to_string(@account.role))}
              </dd>
            </div>

            <div>
              <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wide">
                Status
              </dt>
              <dd class="mt-1" {test_id("account-status")}>
                <%= if @account.deactivated_at do %>
                  <span class="text-ds-error text-sm font-medium">Deactivated</span>
                <% else %>
                  <span class="text-ds-primary text-sm font-medium">Active</span>
                <% end %>
              </dd>
            </div>

            <div>
              <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wide">
                Organizations
              </dt>
              <dd class="mt-1 flex flex-wrap gap-1" {test_id("account-organizations")}>
                <%= if @account.organizations == [] do %>
                  <span class="text-sm text-ds-on-surface-variant">None</span>
                <% else %>
                  <span
                    :for={org <- @account.organizations}
                    class="inline-block bg-ds-surface-high rounded-full px-2 py-0.5 text-xs"
                  >
                    {org.name}
                  </span>
                <% end %>
              </dd>
            </div>

            <%= if @account.deactivated_at do %>
              <div>
                <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wide">
                  Deactivated By
                </dt>
                <dd
                  class="mt-1 text-sm text-ds-on-surface-variant"
                  {test_id("account-deactivated-by")}
                >
                  <%= if @account.deactivator do %>
                    {@account.deactivator.email}
                  <% else %>
                    Unknown
                  <% end %>
                </dd>
              </div>
            <% end %>
          </dl>

          <div class="mt-6 pt-6 border-t border-ds-outline-variant/20 flex gap-3">
            <%= if is_nil(@account.deactivated_at) and @account.id != @current_scope.account.id do %>
              <button
                phx-click="request_deactivate"
                class="rounded-ds-sharp bg-ds-error px-4 py-2 text-sm font-ds-body font-medium text-ds-on-error hover:bg-ds-error/90 transition-colors"
                {test_id("account-deactivate-btn")}
              >
                Deactivate
              </button>
            <% end %>

            <%= if @account.deactivated_at && @account.id != @current_scope.account.id do %>
              <button
                phx-click="request_reactivate"
                class="rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
                {test_id("account-reactivate-btn")}
              >
                Reactivate
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
          <div class="bg-ds-surface-card rounded-ds-sharp p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-ds-heading font-bold text-ds-on-surface mb-2">
              Deactivate Account
            </h3>
            <p class="text-sm text-ds-on-surface-variant mb-6">
              Are you sure you want to deactivate <strong>{@account.email}</strong>?
              They will be immediately logged out and unable to log in.
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_deactivate"
                class="rounded-ds-sharp px-4 py-2 text-sm font-ds-body font-medium text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
                {test_id("deactivate-cancel-btn")}
              >
                Cancel
              </button>
              <button
                phx-click="confirm_deactivate"
                class="rounded-ds-sharp bg-ds-error px-4 py-2 text-sm font-ds-body font-medium text-ds-on-error hover:bg-ds-error/90 transition-colors"
                {test_id("deactivate-confirm-btn")}
              >
                Deactivate
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
          <div class="bg-ds-surface-card rounded-ds-sharp p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-ds-heading font-bold text-ds-on-surface mb-2">
              Reactivate Account
            </h3>
            <p class="text-sm text-ds-on-surface-variant mb-6">
              Are you sure you want to reactivate <strong>{@account.email}</strong>?
              They will be able to log in again.
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_reactivate"
                class="rounded-ds-sharp px-4 py-2 text-sm font-ds-body font-medium text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
                {test_id("reactivate-cancel-btn")}
              >
                Cancel
              </button>
              <button
                phx-click="confirm_reactivate"
                class="rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
                {test_id("reactivate-confirm-btn")}
              >
                Reactivate
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
