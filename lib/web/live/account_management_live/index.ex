defmodule Web.AccountManagementLive.Index do
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
  def mount(_params, _session, socket) do
    accounts = Identity.list_accounts()

    {:ok,
     socket
     |> assign(:page_title, gettext("Accounts"))
     |> assign(:accounts, accounts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center justify-between px-4 sm:px-6 lg:px-8 py-3">
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click={toggle_nav_drawer()}
              class="p-2 -ml-2 text-cm-text-muted hover:text-cm-black lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
              aria-label={gettext("Open menu")}
              {test_id("hamburger-menu")}
            >
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <h1 class="text-lg font-cm-display font-bold text-cm-black">
              {gettext("Accounts")}
            </h1>
          </div>
          <.link
            navigate={~p"/admin/accounts/new"}
            class="hidden lg:inline-flex items-center gap-2 rounded-cm bg-cm-indigo px-4 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-indigo/90 transition-colors"
            {test_id("account-new-btn")}
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("New Account")}
          </.link>
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

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6" {test_id("accounts-table")}>
        <%!-- Mobile: card layout --%>
        <div class="lg:hidden space-y-3">
          <.link
            navigate={~p"/admin/accounts/new"}
            class="inline-flex items-center gap-2 rounded-cm bg-cm-indigo px-4 py-2 text-sm font-cm-body font-medium text-cm-white hover:bg-cm-indigo/90 transition-colors mb-2"
            {test_id("account-new-btn-mobile")}
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("New Account")}
          </.link>

          <.link
            :for={account <- @accounts}
            navigate={~p"/admin/accounts/#{account.id}"}
            class={[
              "block rounded-cm bg-cm-white p-4",
              if(account.deactivated_at, do: "opacity-50")
            ]}
            {test_id("account-row-#{account.id}")}
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="font-cm-body font-medium text-cm-black truncate">
                  {account.name || account.email}
                </p>
                <p :if={account.name} class="text-xs text-cm-text-muted truncate">
                  {account.email}
                </p>
              </div>
              <div class="flex-shrink-0 flex items-center gap-2">
                <span class="capitalize text-xs text-cm-text-muted bg-cm-surface rounded-full px-2 py-0.5">
                  {account.role}
                </span>
                <%= if account.deactivated_at do %>
                  <span
                    class="text-cm-error text-xs font-medium"
                    {test_id("account-status-#{account.id}")}
                  >
                    {gettext("Deactivated")}
                  </span>
                <% else %>
                  <span
                    class="text-cm-indigo text-xs font-medium"
                    {test_id("account-status-#{account.id}")}
                  >
                    {gettext("Active")}
                  </span>
                <% end %>
              </div>
            </div>
            <div :if={account.organizations != []} class="mt-2 flex flex-wrap gap-1">
              <span
                :for={org <- account.organizations}
                class="inline-block bg-cm-surface rounded-full px-2 py-0.5 text-xs"
              >
                {org.name}
              </span>
            </div>
          </.link>
        </div>

        <%!-- Desktop: table layout --%>
        <div class="hidden lg:block">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-cm-border/20 text-left text-cm-text-muted">
                <th class="pb-3 pr-4 font-medium">{gettext("Name")}</th>
                <th class="pb-3 pr-4 font-medium">{gettext("Email")}</th>
                <th class="pb-3 pr-4 font-medium">{gettext("Role")}</th>
                <th class="pb-3 pr-4 font-medium">{gettext("Organizations")}</th>
                <th class="pb-3 pr-4 font-medium">{gettext("Status")}</th>
                <th class="pb-3 font-medium"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={account <- @accounts}
                class={[
                  "border-b border-cm-border/10",
                  if(account.deactivated_at, do: "opacity-50")
                ]}
                {test_id("account-row-#{account.id}")}
              >
                <td class="py-3 pr-4">{account.name || "—"}</td>
                <td class="py-3 pr-4">{account.email}</td>
                <td class="py-3 pr-4 capitalize">{account.role}</td>
                <td class="py-3 pr-4">
                  <span
                    :for={org <- account.organizations}
                    class="inline-block bg-cm-surface rounded-full px-2 py-0.5 text-xs mr-1 mb-1"
                  >
                    {org.name}
                  </span>
                </td>
                <td class="py-3 pr-4">
                  <%= if account.deactivated_at do %>
                    <span
                      class="text-cm-error text-xs font-medium"
                      {test_id("account-status-#{account.id}")}
                    >
                      {gettext("Deactivated")}
                    </span>
                  <% else %>
                    <span
                      class="text-cm-indigo text-xs font-medium"
                      {test_id("account-status-#{account.id}")}
                    >
                      {gettext("Active")}
                    </span>
                  <% end %>
                </td>
                <td class="py-3 text-right">
                  <.link
                    navigate={~p"/admin/accounts/#{account.id}"}
                    class="text-cm-indigo hover:underline text-xs mr-2"
                  >
                    {gettext("View")}
                  </.link>
                  <.link
                    navigate={~p"/admin/accounts/#{account.id}/edit"}
                    class="text-cm-indigo hover:underline text-xs"
                  >
                    {gettext("Edit")}
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
