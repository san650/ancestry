defmodule Web.Components.NavDrawer do
  @moduledoc """
  Unified navigation drawer for mobile. Slides from the left.
  Contains page actions (slot), page panel (slot), org list, and account links.
  On desktop (lg:), the drawer is hidden — header bar and toolbar buttons remain.
  """
  use Phoenix.Component
  use Gettext, backend: Web.Gettext

  import Web.CoreComponents, only: [icon: 1]
  import Web.Helpers.TestHelpers
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
        "fixed top-0 left-0 bottom-0 z-50 w-[85vw] max-w-sm bg-cm-white overflow-y-auto",
        "transition-transform duration-200 ease-out",
        "lg:hidden",
        "-translate-x-full"
      ]}
      aria-label={gettext("Navigation")}
      phx-window-keydown={toggle_nav_drawer(@id)}
      phx-key="Escape"
    >
      <%!-- Header: logo + close --%>
      <div class="flex items-center justify-between p-4 border-b border-cm-border/20">
        <a {test_id("nav-logo")} href="/org" class="flex items-center gap-3">
          <div class="w-8 h-8 border-[2.5px] border-cm-indigo rounded-cm flex items-center justify-center">
            <span class="font-cm-display text-cm-indigo text-base leading-none">A</span>
          </div>
          <span class="font-cm-display text-cm-indigo tracking-[2px] text-lg uppercase">
            {gettext("Ancestry")}
          </span>
        </a>
        <button
          type="button"
          phx-click={toggle_nav_drawer(@id)}
          class="p-2 rounded-cm text-cm-text-muted hover:bg-cm-surface min-w-[44px] min-h-[44px] flex items-center justify-center"
          aria-label={gettext("Close menu")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <%!-- Page actions section --%>
      <%= if @page_actions != [] do %>
        <div class="px-4 pt-4 pb-2">
          <p class="font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-text-muted px-2 pb-2">
            {gettext("Page Actions")}
          </p>
          {render_slot(@page_actions)}
        </div>
        <div class="mx-4 border-b border-cm-border/20" />
      <% end %>

      <%!-- Page panel section (e.g., people search + galleries) --%>
      <%= if @page_panel != [] do %>
        <div class="px-4 pt-4 pb-2">
          {render_slot(@page_panel)}
        </div>
        <div class="mx-4 border-b border-cm-border/20" />
      <% end %>

      <%!-- Account section --%>
      <%= if @current_scope && @current_scope.account do %>
        <div class="border-t border-cm-border/20 mx-4 my-1" />
        <div class="px-2 pt-2 pb-6">
          <.link
            {test_id("nav-settings")}
            href="/accounts/settings"
            class={[
              "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
              "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
              "transition-colors text-cm-black hover:bg-cm-surface"
            ]}
          >
            {gettext("Settings")}
          </.link>
          <%= if can?(@current_scope, :index, Ancestry.Identity.Account) do %>
            <.link
              {test_id("nav-accounts")}
              href="/admin/accounts"
              class={[
                "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
                "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
                "transition-colors text-cm-black hover:bg-cm-surface"
              ]}
            >
              {gettext("Accounts")}
            </.link>
          <% end %>
          <%= if can?(@current_scope, :index, Ancestry.Audit.Log) do %>
            <.link
              {test_id("nav-audit-log-admin")}
              href="/admin/audit-log"
              class={[
                "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
                "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
                "transition-colors text-cm-black hover:bg-cm-surface"
              ]}
            >
              {gettext("Audit log")}
            </.link>
            <%= if @current_scope.organization do %>
              <.link
                {test_id("nav-audit-log-org")}
                href={"/org/#{@current_scope.organization.id}/audit-log"}
                class={[
                  "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
                  "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
                  "transition-colors text-cm-black hover:bg-cm-surface"
                ]}
              >
                {gettext("Audit log (org)")}
              </.link>
            <% end %>
          <% end %>
          <.link
            {test_id("nav-logout")}
            href="/accounts/log-out"
            method="delete"
            class={[
              "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
              "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
              "transition-colors text-cm-black hover:bg-cm-surface"
            ]}
          >
            {gettext("Log out")}
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
  Renders text-only (no icons). When `navigate` is set, renders a `<.link>`;
  otherwise renders a `<button>`.

  The `icon` attribute is accepted but ignored — kept for backward compatibility
  with existing pages that still pass it. It will be removed in a future cleanup.
  """
  attr :icon, :string, default: nil
  attr :label, :string, required: true
  attr :danger, :boolean, default: false
  attr :navigate, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id)

  def nav_action(assigns) do
    ~H"""
    <%= if @navigate do %>
      <.link
        navigate={@navigate}
        class={[
          "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
          "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
          "transition-colors",
          if(@danger,
            do: "text-cm-error hover:bg-cm-error/10",
            else: "text-cm-black hover:bg-cm-surface"
          )
        ]}
        {@rest}
      >
        {@label}
      </.link>
    <% else %>
      <button
        type="button"
        class={[
          "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
          "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
          "transition-colors",
          if(@danger,
            do: "text-cm-error hover:bg-cm-error/10",
            else: "text-cm-black hover:bg-cm-surface"
          )
        ]}
        {@rest}
      >
        {@label}
      </button>
    <% end %>
    """
  end

  @doc """
  A visual separator line for use inside the nav drawer.
  """
  def nav_separator(assigns) do
    ~H"""
    <div class="border-t border-cm-border my-1 mx-4"></div>
    """
  end
end
