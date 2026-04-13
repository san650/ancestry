defmodule Web.Components.NavDrawer do
  @moduledoc """
  Unified navigation drawer for mobile. Slides from the left.
  Contains page actions (slot), page panel (slot), org list, and account links.
  On desktop (lg:), the drawer is hidden — header bar and toolbar buttons remain.
  """
  use Phoenix.Component
  use Gettext, backend: Web.Gettext

  import Web.CoreComponents, only: [icon: 1]
  import Ancestry.Authorization, only: [can?: 3]

  alias Phoenix.LiveView.JS

  attr :id, :string, default: "nav-drawer"
  attr :current_scope, :map, default: nil
  slot :page_actions, doc: "Page-specific action items (edit, delete, etc.)"

  slot :page_panel,
    doc: "Page-specific panel content (e.g., people search + gallery list on Family Show)"

  slot :inner_block

  def nav_drawer(assigns) do
    ~H"""
    <%!-- Backdrop --%>
    <div
      id={"#{@id}-backdrop"}
      class="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm transition-opacity duration-200 lg:hidden opacity-0 pointer-events-none"
      phx-click={toggle_nav_drawer(@id)}
      aria-hidden="true"
    />
    <%!-- Drawer panel — slides from the LEFT --%>
    <aside
      id={@id}
      class={[
        "fixed top-0 left-0 bottom-0 z-50 w-[85vw] max-w-sm bg-ds-surface-card overflow-y-auto",
        "transition-transform duration-200 ease-out",
        "lg:hidden",
        "-translate-x-full"
      ]}
      aria-label={gettext("Navigation")}
      phx-window-keydown={toggle_nav_drawer(@id)}
      phx-key="Escape"
    >
      <%!-- Header: logo + close --%>
      <div class="flex items-center justify-between p-4 border-b border-ds-outline-variant/20">
        <a href="/" class="flex items-center gap-2">
          <img src="/images/logo.png" width="32" class="rounded-ds-sharp" />
          <span class="font-ds-heading font-bold text-ds-on-surface">{gettext("Ancestry")}</span>
        </a>
        <button
          type="button"
          phx-click={toggle_nav_drawer(@id)}
          class="p-2 rounded-ds-sharp text-ds-on-surface-variant hover:bg-ds-surface-high min-w-[44px] min-h-[44px] flex items-center justify-center"
          aria-label={gettext("Close menu")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <%!-- Page actions section --%>
      <%= if @page_actions != [] do %>
        <div class="px-4 pt-4 pb-2">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-ds-on-surface-variant px-2 pb-2">
            {gettext("Page Actions")}
          </p>
          {render_slot(@page_actions)}
        </div>
        <div class="mx-4 border-b border-ds-outline-variant/20" />
      <% end %>

      <%!-- Page panel section (e.g., people search + galleries) --%>
      <%= if @page_panel != [] do %>
        <div class="px-4 pt-4 pb-2">
          {render_slot(@page_panel)}
        </div>
        <div class="mx-4 border-b border-ds-outline-variant/20" />
      <% end %>

      <%!-- Organizations section --%>
      <%= if @current_scope && @current_scope.account do %>
        <div class="px-4 pt-4 pb-2">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-ds-on-surface-variant px-2 pb-2">
            {gettext("Organizations")}
          </p>
          {render_slot(@inner_block)}
        </div>
        <div class="mx-4 border-b border-ds-outline-variant/20" />

        <%!-- Account section --%>
        <div class="px-4 pt-4 pb-6">
          <.link
            href="/accounts/settings"
            class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
          >
            <.icon name="hero-cog-6-tooth" class="size-5 shrink-0 text-ds-on-surface-variant" />
            <span class="font-ds-body text-sm">{gettext("Settings")}</span>
          </.link>
          <%= if can?(@current_scope, :index, Ancestry.Identity.Account) do %>
            <.link
              href="/admin/accounts"
              class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
            >
              <.icon name="hero-users" class="size-5 shrink-0 text-ds-on-surface-variant" />
              <span class="font-ds-body text-sm">{gettext("Accounts")}</span>
            </.link>
          <% end %>
          <.link
            href="/accounts/log-out"
            method="delete"
            class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
          >
            <.icon
              name="hero-arrow-right-start-on-rectangle"
              class="size-5 shrink-0 text-ds-on-surface-variant"
            />
            <span class="font-ds-body text-sm">{gettext("Log out")}</span>
          </.link>
        </div>
      <% end %>
    </aside>
    """
  end

  @doc """
  Toggles the nav drawer open/closed.
  """
  def toggle_nav_drawer(id \\ "nav-drawer") do
    JS.toggle_class("-translate-x-full translate-x-0", to: "##{id}")
    |> JS.toggle_class("opacity-0 pointer-events-none", to: "##{id}-backdrop")
  end

  @doc """
  A single action row for use inside the nav drawer's page_actions slot.
  Same API as Mobile.sheet_action for easy migration.
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :danger, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-id)

  def nav_action(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px]",
        "transition-colors hover:bg-ds-surface-high",
        if(@danger, do: "text-ds-error", else: "text-ds-on-surface")
      ]}
      {@rest}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span class="font-ds-body text-sm">{@label}</span>
    </button>
    """
  end
end
