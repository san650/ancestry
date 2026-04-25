defmodule Web.Components.Mobile do
  @moduledoc """
  Mobile-first shared components: drawer, bottom sheet, full-screen overlay.
  """
  use Phoenix.Component

  import Web.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  A slide-in drawer panel. On mobile, slides in from the right with a backdrop.
  On `lg:` screens, renders inline (no transform, no backdrop).

  ## Attrs
  - `id` (required) — unique DOM id
  - `open` — whether the drawer starts open (default: false)

  ## Slots
  - `inner_block` — drawer content
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  slot :inner_block, required: true

  def drawer(assigns) do
    ~H"""
    <%!-- Backdrop: visible on mobile only when drawer is open --%>
    <div
      id={"#{@id}-backdrop"}
      class={[
        "fixed inset-0 z-40 bg-black/60 backdrop-blur-sm transition-opacity duration-200 lg:hidden",
        unless(@open, do: "opacity-0 pointer-events-none")
      ]}
      phx-click={toggle_drawer(@id)}
      aria-hidden="true"
    />
    <%!-- Drawer panel --%>
    <aside
      id={@id}
      class={[
        "fixed top-0 right-0 bottom-0 z-50 w-[85vw] max-w-sm bg-cm-white overflow-y-auto",
        "transition-transform duration-200 ease-out",
        "lg:static lg:w-auto lg:max-w-none lg:z-auto lg:translate-x-0 lg:transition-none",
        if(@open, do: "translate-x-0", else: "translate-x-full")
      ]}
      aria-label="Side panel"
    >
      <div class="flex items-center justify-between p-4 lg:hidden">
        <span class="font-cm-display font-bold text-cm-black">Menu</span>
        <button
          type="button"
          phx-click={toggle_drawer(@id)}
          class="p-2 rounded-cm text-cm-text-muted hover:bg-cm-surface"
          aria-label="Close menu"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
      {render_slot(@inner_block)}
    </aside>
    """
  end

  @doc """
  Toggles a drawer open/closed by toggling CSS classes on the panel and backdrop.
  """
  def toggle_drawer(id) do
    JS.toggle_class("translate-x-full translate-x-0", to: "##{id}")
    |> JS.toggle_class("opacity-0 pointer-events-none", to: "##{id}-backdrop")
  end

  @doc """
  A bottom sheet menu for mobile. Shows action items sliding up from the bottom.
  On desktop, this component is not rendered — the parent should render actions
  directly in the toolbar instead.

  ## Attrs
  - `id` (required) — unique DOM id

  ## Slots
  - `inner_block` — action items (typically a list of buttons)
  """
  attr :id, :string, required: true
  slot :inner_block, required: true

  def bottom_sheet(assigns) do
    ~H"""
    <%!-- Backdrop --%>
    <div
      id={"#{@id}-backdrop"}
      class="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm transition-opacity duration-200 opacity-0 pointer-events-none"
      phx-click={toggle_bottom_sheet(@id)}
      aria-hidden="true"
    />
    <%!-- Sheet --%>
    <div
      id={@id}
      class="fixed bottom-0 left-0 right-0 z-50 bg-cm-white rounded-t-lg translate-y-full transition-transform duration-200 ease-out pb-[env(safe-area-inset-bottom)]"
      role="menu"
      aria-label="Actions"
    >
      <div class="flex justify-center pt-3 pb-1">
        <div class="w-10 h-1 rounded-full bg-cm-border/40" />
      </div>
      <div class="px-4 pb-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Toggles a bottom sheet open/closed.
  """
  def toggle_bottom_sheet(id) do
    JS.toggle_class("translate-y-full translate-y-0", to: "##{id}")
    |> JS.toggle_class("opacity-0 pointer-events-none", to: "##{id}-backdrop")
  end

  @doc """
  A single action row for use inside a bottom sheet.

  ## Attrs
  - `icon` — Heroicon name (e.g., "hero-pencil-square")
  - `label` — Action text
  - `danger` — whether this is a destructive action (red text)
  - rest — any additional HTML attributes (phx-click, etc.)
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :danger, :boolean, default: false
  attr :rest, :global, include: ~w(phx-click phx-value-id)

  def sheet_action(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex items-center gap-3 w-full px-2 py-3 text-left rounded-cm min-h-[48px]",
        "transition-colors hover:bg-cm-surface",
        if(@danger, do: "text-cm-error", else: "text-cm-black")
      ]}
      role="menuitem"
      {@rest}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span class="font-cm-body text-sm">{@label}</span>
    </button>
    """
  end
end
