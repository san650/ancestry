defmodule Web.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use Web, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  Use the `:toolbar` slot to render page-specific actions below the navbar:

      <Layouts.app flash={@flash}>
        <:toolbar>
          <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
            <h1>Page Title</h1>
            <button>Action</button>
          </div>
        </:toolbar>
        <div>page content</div>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true
  slot :toolbar, doc: "optional toolbar rendered below the navbar"

  def app(assigns) do
    ~H"""
    <div class="min-h-screen" style="--toolbar-height: 57px">
      <header class="hidden lg:flex items-center px-4 sm:px-6 lg:px-8 py-2 bg-cm-indigo border-b-[3px] border-cm-coral">
        <div class="flex-1">
          <a href="/org" class="flex-1 flex w-fit items-center gap-3">
            <div class="w-9 h-9 border-[2.5px] border-cm-white rounded-cm flex items-center justify-center">
              <span class="font-cm-display text-cm-white text-lg leading-none">A</span>
            </div>
            <span class="font-cm-display text-cm-white tracking-[2px] text-lg">
              {gettext("ANCESTRY")}
            </span>
          </a>
        </div>
        <div class="flex-none">
          <ul class="flex flex-row px-1 items-center gap-4 font-cm-mono text-[10px] uppercase tracking-wider text-cm-white/50">
            <%= if @current_scope && @current_scope.account do %>
              <%= if @current_scope.organization do %>
                <li>
                  <.link
                    navigate={~p"/org/#{@current_scope.organization.id}"}
                    class="text-cm-golden hover:text-cm-white transition-colors"
                  >
                    {@current_scope.organization.name}
                  </.link>
                </li>
              <% else %>
                <li>
                  <.link href={~p"/org"} class="hover:text-cm-white transition-colors">
                    {gettext("Organizations")}
                  </.link>
                </li>
              <% end %>
              <%= if can?(@current_scope, :index, Ancestry.Identity.Account) do %>
                <li>
                  <.link href={~p"/admin/accounts"} class="hover:text-cm-white transition-colors">
                    {gettext("Accounts")}
                  </.link>
                </li>
              <% end %>
              <%= if can?(@current_scope, :index, Ancestry.Audit.Log) do %>
                <li>
                  <.link
                    {test_id("nav-audit-log-admin")}
                    href={~p"/admin/audit-log"}
                    class="hover:text-cm-white transition-colors"
                  >
                    {gettext("Audit log")}
                  </.link>
                </li>
                <%= if @current_scope.organization do %>
                  <li>
                    <.link
                      {test_id("nav-audit-log-org")}
                      href={"/org/#{@current_scope.organization.id}/audit-log"}
                      class="hover:text-cm-white transition-colors"
                    >
                      {gettext("Audit log (org)")}
                    </.link>
                  </li>
                <% end %>
              <% end %>
              <li class="text-cm-white/20">|</li>
              <li class="text-cm-white/70">{@current_scope.account.email}</li>
              <li>
                <.link
                  href={~p"/accounts/settings"}
                  class="p-2 hover:text-cm-white transition-colors"
                >
                  {gettext("Settings")}
                </.link>
              </li>
              <li>
                <.link
                  href={~p"/accounts/log-out"}
                  method="delete"
                  class="p-2 hover:text-cm-white transition-colors"
                >
                  {gettext("Log out")}
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
      </header>

      <%= if @toolbar != [] do %>
        <div
          id="toolbar"
          class="sticky z-1 top-0 bg-cm-surface border-b border-cm-border"
        >
          <div class="font-cm-mono text-[10px] text-cm-text-muted">
            {render_slot(@toolbar)}
          </div>
        </div>
      <% end %>

      <main class="min-h-100">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Minimal layout for print pages. No header, toolbar, or navigation.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def print(assigns) do
    ~H"""
    <div class="bg-white min-h-screen p-2">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed top-4 right-4 z-50 flex flex-col gap-2" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center bg-cm-surface rounded-full">
      <div class="absolute w-1/3 h-full rounded-full bg-cm-white brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
