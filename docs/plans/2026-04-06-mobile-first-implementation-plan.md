# Mobile-First Design Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the four priority pages (Family Show, Gallery Show, Person Show, Login) to be mobile-first, adhering to DESIGN.md and the decisions in COMPONENTS.jsonl.

**Architecture:** Component-by-component refactor. Shared primitives (drawer, bottom sheet, full-screen overlay) are built in Task 1, then applied to each page in order. Each page's template is restructured so mobile is the default and desktop enhancements use `sm:`/`md:`/`lg:` responsive utilities. JS hooks are added only where needed (swipe gesture for lightbox). All state for drawer/bottom sheet uses `Phoenix.LiveView.JS` for instant client-side toggling.

**Tech Stack:** Phoenix LiveView 1.0, Tailwind CSS v4 (mobile-first), Phoenix.LiveView.JS for client-side interactions, vanilla JS hooks for swipe gestures.

**Validation:** The running app at `http://localhost:4000/` (user: `san650@gmail.com`, password: `012345678912`) should be checked after each task to verify the UI renders correctly on both mobile and desktop viewports.

**Key references:**
- Spec: `docs/plans/2026-04-06-mobile-first-design-spec.md`
- Design rules: `DESIGN.md`
- Component decisions: `COMPONENTS.jsonl` (grep for component names)
- Learnings: `docs/learnings.md`

---

## File Map

### New files
- `lib/web/components/mobile.ex` — Shared mobile-first components (drawer, bottom_sheet, full_screen_overlay)
- `assets/js/swipe.js` — Swipe gesture detection hook for lightbox

### Modified files
- `assets/css/app.css` — Add scrollbar-hiding utility, safe-area utilities
- `assets/js/app.js` — Register Swipe hook
- `lib/web/components/layouts.ex` — Responsive header adjustments
- `lib/web/live/family_live/show.html.heex` — Mobile-first tree layout, drawer, bottom sheet
- `lib/web/live/family_live/show.ex` — Drawer people search events
- `lib/web/live/family_live/side_panel_component.ex` — Restructure for drawer/inline dual rendering
- `lib/web/live/family_live/person_card_component.ex` — Accessibility attrs, tap-to-focus interaction
- `lib/web/live/gallery_live/show.html.heex` — Mobile toolbar, bottom sheet, selection bar
- `lib/web/live/gallery_live/show.ex` — Bottom sheet state (if needed)
- `lib/web/components/photo_gallery.ex` — Mobile lightbox (swipe, no thumbnails, position indicator), responsive grid breakpoints, disable tagging on mobile
- `lib/web/live/person_live/show.html.heex` — Hero photo header, mobile content reorder, bottom sheet
- `lib/web/live/person_live/show.ex` — Any needed assign changes
- `lib/web/live/account_live/login.ex` — Full-screen mobile-first login form

---

## Task 1: Shared Components & CSS Utilities

Build the reusable mobile-first primitives that all pages will use.

**Files:**
- Create: `lib/web/components/mobile.ex`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Add CSS utilities for scrollbar hiding and safe-area**

In `assets/css/app.css`, after the masonry grid CSS (line 88-90), add:

```css
/* Scrollbar hiding — preserves scroll functionality */
.hide-scrollbar {
  scrollbar-width: none;
}
.hide-scrollbar::-webkit-scrollbar {
  display: none;
}
```

- [ ] **Step 2: Run the app and verify CSS compiles**

Run: `mix phx.server` (or check already-running server)
Expected: No CSS compilation errors, app loads normally.

- [ ] **Step 3: Create the shared mobile components module**

Create `lib/web/components/mobile.ex` with three components:

```elixir
defmodule Web.Components.Mobile do
  @moduledoc """
  Mobile-first shared components: drawer, bottom sheet, full-screen overlay.
  """
  use Phoenix.Component

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
        "fixed top-0 right-0 bottom-0 z-50 w-[85vw] max-w-sm bg-ds-surface-card overflow-y-auto",
        "transition-transform duration-200 ease-out",
        "lg:static lg:w-auto lg:max-w-none lg:z-auto lg:translate-x-0 lg:transition-none",
        if(@open, do: "translate-x-0", else: "translate-x-full")
      ]}
      aria-label="Side panel"
    >
      <div class="flex items-center justify-between p-4 lg:hidden">
        <span class="font-ds-heading font-bold text-ds-on-surface">Menu</span>
        <button
          type="button"
          phx-click={toggle_drawer(@id)}
          class="p-2 rounded-ds-sharp text-ds-on-surface-variant hover:bg-ds-surface-high"
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
      class="fixed bottom-0 left-0 right-0 z-50 bg-ds-surface-card rounded-t-lg translate-y-full transition-transform duration-200 ease-out pb-[env(safe-area-inset-bottom)]"
      role="menu"
      aria-label="Actions"
    >
      <div class="flex justify-center pt-3 pb-1">
        <div class="w-10 h-1 rounded-full bg-ds-outline-variant/40" />
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
        "flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[48px]",
        "transition-colors hover:bg-ds-surface-high",
        if(@danger, do: "text-ds-error", else: "text-ds-on-surface")
      ]}
      role="menuitem"
      {@rest}
    >
      <.icon name={@icon} class="size-5 shrink-0" />
      <span class="font-ds-body text-sm">{@label}</span>
    </button>
    """
  end

  defp icon(assigns) do
    Web.CoreComponents.icon(assigns)
  end
end
```

- [ ] **Step 4: Import the mobile components in the web module**

In `lib/web.ex`, inside the `html_helpers` function that is imported by all LiveViews and components, add:

```elixir
import Web.Components.Mobile
```

Find the existing `import Web.CoreComponents` line and add the new import below it.

- [ ] **Step 5: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation, no warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/web/components/mobile.ex assets/css/app.css lib/web.ex
git commit -m "feat: add shared mobile-first components (drawer, bottom sheet) and CSS utilities"
```

---

## Task 2: Family Show — Mobile-First Layout & Drawer

Restructure the Family Show page to use the drawer for the side panel on mobile and the bottom sheet for toolbar actions.

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex` (686 lines)
- Modify: `lib/web/live/family_live/show.ex` (487 lines)
- Modify: `lib/web/live/family_live/side_panel_component.ex` (153 lines)

- [ ] **Step 1: Read the current Family Show template and LiveView module**

Read `lib/web/live/family_live/show.html.heex` and `lib/web/live/family_live/show.ex` completely to understand the current structure before making changes.

- [ ] **Step 2: Restructure the toolbar (lines 1-70 of show.html.heex)**

Replace the current toolbar with a mobile-first version:
- Mobile: back arrow + family name + drawer toggle button + bottom sheet trigger (ellipsis)
- Desktop (`lg:`): show edit, delete, kinship buttons directly, hide drawer toggle and ellipsis
- Remove "Create subfamily" and "Manage people" buttons from mobile (they stay on desktop only)
- All buttons must have minimum 44px tap targets (`min-w-[44px] min-h-[44px]`)

The toolbar is inside `<:toolbar>` slot of `<Layouts.app>`. Restructure it as:

```heex
<:toolbar>
  <div class="flex items-center justify-between px-4 py-2 bg-ds-surface-low sm:px-6 lg:px-8">
    <%!-- Left: back + title --%>
    <div class="flex items-center gap-2 min-w-0">
      <.link navigate={~p"/families"} class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Back to families">
        <.icon name="hero-arrow-left" class="size-5" />
      </.link>
      <h1 class="font-ds-heading font-bold text-lg text-ds-on-surface truncate">{@family.name}</h1>
    </div>

    <%!-- Right: actions --%>
    <div class="flex items-center gap-1">
      <%!-- Drawer toggle: mobile only --%>
      <button
        type="button"
        phx-click={toggle_drawer("family-drawer")}
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden"
        aria-label="Open side panel"
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>

      <%!-- Desktop-only actions --%>
      <div class="hidden lg:flex items-center gap-1">
        <.link navigate={~p"/families/#{@family}/kinship"} class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Kinship calculator">
          <.icon name="hero-arrows-right-left" class="size-5" />
        </.link>
        <button type="button" phx-click="edit" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Edit family">
          <.icon name="hero-pencil-square" class="size-5" />
        </button>
        <button type="button" phx-click="request_delete" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Delete family">
          <.icon name="hero-trash" class="size-5" />
        </button>
        <%!-- Desktop-only: manage people, create subfamily --%>
        <button type="button" phx-click="open_manage_people" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Manage people">
          <.icon name="hero-user-group" class="size-5" />
        </button>
      </div>

      <%!-- Bottom sheet trigger: mobile only --%>
      <button
        type="button"
        phx-click={toggle_bottom_sheet("family-actions")}
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden"
        aria-label="More actions"
      >
        <.icon name="hero-ellipsis-vertical" class="size-5" />
      </button>
    </div>
  </div>
</:toolbar>
```

- [ ] **Step 3: Add the bottom sheet for mobile actions**

After the toolbar (before the main content grid), add:

```heex
<%!-- Mobile bottom sheet for actions --%>
<.bottom_sheet id="family-actions">
  <.sheet_action icon="hero-pencil-square" label="Edit family" phx-click={toggle_bottom_sheet("family-actions") |> JS.push("edit")} />
  <.sheet_action icon="hero-trash" label="Delete family" danger phx-click={toggle_bottom_sheet("family-actions") |> JS.push("request_delete")} />
</.bottom_sheet>
```

- [ ] **Step 4: Restructure the main layout grid (lines 72-155)**

Replace the current `grid grid-cols-1 lg:grid-cols-[1fr_18rem]` with:
- On mobile: just the tree canvas (full width)
- On desktop: tree + inline side panel

The drawer wraps the side panel content and handles mobile/desktop rendering automatically:

```heex
<div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] gap-0 lg:gap-4">
  <%!-- Tree canvas: always visible, full width on mobile --%>
  <div class="order-last lg:order-first overflow-auto hide-scrollbar min-h-[60vh]" id="tree-canvas" phx-hook="TreeConnector">
    <%!-- ... existing tree content ... --%>
  </div>

  <%!-- Side panel: drawer on mobile, inline on desktop --%>
  <.drawer id="family-drawer">
    <.live_component
      module={Web.FamilyLive.SidePanelComponent}
      id="side-panel"
      family={@family}
      people={@people}
      galleries={@galleries}
      metrics={@metrics}
      focus_person={@focus_person}
    />
  </.drawer>
</div>
```

- [ ] **Step 5: Add scrollbar hiding to the tree canvas**

The tree canvas `div` should have class `hide-scrollbar` (from our CSS utility) plus `overflow-auto` for natural scroll in both directions. This is already included in the markup above.

- [ ] **Step 6: Restructure SidePanelComponent for drawer/inline use**

Modify `lib/web/live/family_live/side_panel_component.ex` to:
- Remove the `<aside>` wrapper (the drawer component provides the container)
- Add a people search section at the top (type-to-suggest, no pre-populated list)
- Keep the gallery list section below
- On mobile, metrics are hidden (they're secondary info)

The component render should become:

```elixir
def render(assigns) do
  ~H"""
  <div class="flex flex-col gap-6 p-4">
    <%!-- People search: type-to-suggest --%>
    <div>
      <h3 class="font-ds-heading font-bold text-sm text-ds-on-surface-variant mb-2">People</h3>
      <div class="relative">
        <.icon name="hero-magnifying-glass" class="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-ds-on-surface-variant/50" />
        <input
          type="text"
          placeholder="Type to search people"
          phx-change="search_people"
          phx-debounce="300"
          name="query"
          value={@search_query}
          class="w-full pl-10 pr-3 py-2 bg-ds-surface-low border-none rounded-ds-sharp text-sm font-ds-body text-ds-on-surface placeholder:text-ds-on-surface-variant/50 focus:ring-1 focus:ring-ds-primary"
          autocomplete="off"
        />
      </div>
      <%!-- Search results --%>
      <div :if={@search_query != "" && @search_results != []} class="mt-2 flex flex-col gap-1">
        <button
          :for={person <- @search_results}
          type="button"
          phx-click="focus_person_from_search"
          phx-value-id={person.id}
          class="flex items-center gap-3 p-2 rounded-ds-sharp hover:bg-ds-surface-high transition-colors text-left"
        >
          <div class="w-8 h-8 rounded-full bg-ds-surface-high flex items-center justify-center shrink-0 overflow-hidden">
            <%!-- Photo or initials --%>
            <span class="text-xs font-ds-body text-ds-on-surface-variant">{initials(person)}</span>
          </div>
          <span class="text-sm font-ds-body text-ds-on-surface truncate">{person.given_name} {person.surname}</span>
        </button>
      </div>
      <p :if={@search_query != "" && @search_results == []} class="mt-2 text-xs text-ds-on-surface-variant">No results</p>
    </div>

    <%!-- Metrics: desktop only --%>
    <div class="hidden lg:block">
      <%!-- ... existing metrics rendering ... --%>
    </div>

    <%!-- Gallery list --%>
    <div>
      <h3 class="font-ds-heading font-bold text-sm text-ds-on-surface-variant mb-2">Galleries</h3>
      <div class="flex flex-col gap-1">
        <.link
          :for={gallery <- @galleries}
          navigate={~p"/families/#{@family}/galleries/#{gallery}"}
          class="flex items-center gap-3 p-2 rounded-ds-sharp hover:bg-ds-surface-high transition-colors"
        >
          <.icon name="hero-photo" class="size-5 text-ds-on-surface-variant shrink-0" />
          <div class="min-w-0">
            <span class="text-sm font-ds-body text-ds-on-surface truncate block">{gallery.name}</span>
            <span class="text-xs text-ds-on-surface-variant">{length(gallery.photos || [])} photos</span>
          </div>
        </.link>
      </div>
    </div>
  </div>
  """
end
```

- [ ] **Step 7: Add search_people and focus_person_from_search events to show.ex**

Add new assigns in `mount/3`:
```elixir
|> assign(:drawer_search_query, "")
|> assign(:drawer_search_results, [])
```

Add event handlers:
```elixir
def handle_event("search_people", %{"query" => query}, socket) when byte_size(query) >= 2 do
  results = Ancestry.People.search_family_members(socket.assigns.family, query)
  {:noreply, assign(socket, drawer_search_query: query, drawer_search_results: results)}
end

def handle_event("search_people", _params, socket) do
  {:noreply, assign(socket, drawer_search_query: "", drawer_search_results: [])}
end

def handle_event("focus_person_from_search", %{"id" => id}, socket) do
  # Reuse existing focus_person logic, also close drawer via JS
  {:noreply, push_patch(socket, to: ~p"/families/#{socket.assigns.family}?person=#{id}")}
end
```

Note: Check if `Ancestry.People.search_family_members/2` exists. If not, you'll need to use the existing search function or create one. The existing `search_mode` and `search_query` assigns in `show.ex` (lines 255-306) already have search logic — adapt that.

- [ ] **Step 8: Update all modals to be full-screen on mobile**

For each modal in `show.html.heex` (edit, delete, new gallery, delete gallery, person search, add relationship, create subfamily), update the container classes:

Current pattern:
```heex
<div class="fixed inset-0 z-50 flex items-center justify-center">
  <div class="... w-full max-w-md mx-4">
```

New mobile-first pattern:
```heex
<div class="fixed inset-0 z-50 flex items-end lg:items-center justify-center">
  <div class="... w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp">
```

This makes modals slide up as bottom sheets on mobile and stay as centered dialogs on desktop.

- [ ] **Step 9: Verify in browser at mobile and desktop viewports**

Open `http://localhost:4000/` and navigate to a family show page. Check:
- Mobile (375px): Tree fills width, drawer opens from right, bottom sheet slides up
- Desktop (1280px): Side panel inline on right, all toolbar actions visible, no drawer/bottom sheet

- [ ] **Step 10: Commit**

```bash
git add lib/web/live/family_live/show.html.heex lib/web/live/family_live/show.ex lib/web/live/family_live/side_panel_component.ex
git commit -m "feat: mobile-first Family Show with drawer, bottom sheet, and hidden scrollbars"
```

---

## Task 3: Family Show — Tree Interaction & Accessibility

Update person cards for tap-to-focus / tap-focused-to-navigate interaction and accessibility.

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex` (384 lines)

- [ ] **Step 1: Read the current person_card_component.ex**

Read the file completely. Focus on the `person_card/1` function (lines 14-68) and how `focused` state is rendered.

- [ ] **Step 2: Update person_card/1 for accessibility and tap interaction**

The current card has a `<.link navigate=...>` for navigation and a `<button phx-click="focus_person">` wrapper. Per the spec and learnings (`docs/learnings.md` — "Reusable components should not embed navigation behavior"), refactor so:

- The card itself is a `<button>` with `phx-click="focus_person"` (first tap focuses)
- When focused, tapping again navigates (handled in `show.ex` by checking if already focused)
- Add `role="button"`, `aria-label`, `tabindex="0"` for screen readers
- Remove the embedded `<.link>` for navigation (the LiveView handles it)

Update the card markup:
```heex
<button
  type="button"
  phx-click="focus_person"
  phx-value-id={@person.id}
  class={[
    "w-28 rounded-ds-sharp p-2 text-left transition-all duration-150",
    "bg-ds-surface-card",
    gender_border_class(@person),
    if(@focused, do: "ring-2 ring-ds-primary scale-105", else: "hover:bg-ds-surface-high"),
    "focus-visible:outline-2 focus-visible:outline-ds-primary focus-visible:outline-offset-2"
  ]}
  aria-label={"#{@person.given_name} #{@person.surname}"}
  id={"person-card-#{@person.id}"}
>
  <%!-- Card content (photo, name, lifespan) — no nested links --%>
</button>
```

- [ ] **Step 3: Update focus_person handler in show.ex for tap-to-navigate**

In `lib/web/live/family_live/show.ex`, update the `handle_event("focus_person", ...)` handler (around line 96-102):

```elixir
def handle_event("focus_person", %{"id" => id}, socket) do
  person_id = String.to_integer(id)

  if socket.assigns.focus_person && socket.assigns.focus_person.id == person_id do
    # Already focused — navigate to profile (second tap)
    person = Enum.find(socket.assigns.people, &(&1.id == person_id))
    {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family}/people/#{person}")}
  else
    # First tap — focus this person
    {:noreply, push_patch(socket, to: ~p"/families/#{socket.assigns.family}?person=#{person_id}")}
  end
end
```

- [ ] **Step 4: Verify tap interaction**

Open a family show page in the browser. Click a person card:
- First click: card gets ring highlight, tree centers on them
- Second click on same card: navigates to their profile page

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex lib/web/live/family_live/show.ex
git commit -m "feat: tap-to-focus/tap-to-navigate on person cards with a11y attrs"
```

---

## Task 4: Gallery Show — Mobile Toolbar & Bottom Sheet

Restructure the Gallery Show toolbar and add the bottom sheet for secondary actions.

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex` (327 lines)

- [ ] **Step 1: Read the current gallery show template**

Read `lib/web/live/gallery_live/show.html.heex` completely.

- [ ] **Step 2: Restructure the toolbar (lines 1-53)**

Replace the current toolbar with mobile-first layout:
- Mobile: back arrow + gallery name + select button (primary) + ellipsis (bottom sheet trigger)
- Desktop (`lg:`): show select, upload, layout toggle directly

```heex
<:toolbar>
  <div class="flex items-center justify-between px-4 py-2 bg-ds-surface-low sm:px-6 lg:px-8">
    <div class="flex items-center gap-2 min-w-0">
      <.link navigate={~p"/families/#{@family}/galleries"} class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Back to galleries">
        <.icon name="hero-arrow-left" class="size-5" />
      </.link>
      <h1 class="font-ds-heading font-bold text-lg text-ds-on-surface truncate">{@gallery.name}</h1>
    </div>

    <div class="flex items-center gap-1">
      <%!-- Select: always visible (primary mobile action) --%>
      <button
        type="button"
        phx-click="toggle_select_mode"
        class={[
          "p-2 rounded-ds-sharp transition-colors",
          if(@selection_mode, do: "bg-ds-primary text-ds-on-primary", else: "text-ds-on-surface-variant hover:text-ds-on-surface")
        ]}
        aria-label={if(@selection_mode, do: "Exit selection", else: "Select photos")}
      >
        <.icon name="hero-check-circle" class="size-5" />
      </button>

      <%!-- Desktop-only actions --%>
      <div class="hidden lg:flex items-center gap-1">
        <button type="button" phx-click={JS.dispatch("click", to: "#upload-form input[type=file]")} class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Upload photos">
          <.icon name="hero-arrow-up-tray" class="size-5" />
        </button>
        <button type="button" phx-click="toggle_layout" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Toggle layout">
          <.icon name={if(@grid_layout == :masonry, do: "hero-squares-2x2", else: "hero-view-columns")} class="size-5" />
        </button>
      </div>

      <%!-- Bottom sheet trigger: mobile only --%>
      <button
        type="button"
        phx-click={toggle_bottom_sheet("gallery-actions")}
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden"
        aria-label="More actions"
      >
        <.icon name="hero-ellipsis-vertical" class="size-5" />
      </button>
    </div>
  </div>
</:toolbar>
```

- [ ] **Step 3: Add the gallery bottom sheet**

After the toolbar, add:

```heex
<.bottom_sheet id="gallery-actions">
  <.sheet_action
    icon="hero-arrow-up-tray"
    label="Upload photos"
    phx-click={toggle_bottom_sheet("gallery-actions") |> JS.dispatch("click", to: "#upload-form input[type=file]")}
  />
  <.sheet_action
    icon={if(@grid_layout == :masonry, do: "hero-squares-2x2", else: "hero-view-columns")}
    label={if(@grid_layout == :masonry, do: "Uniform grid", else: "Masonry layout")}
    phx-click={toggle_bottom_sheet("gallery-actions") |> JS.push("toggle_layout")}
  />
</.bottom_sheet>
```

- [ ] **Step 4: Add selection mode bottom action bar**

When in selection mode, show a fixed bottom bar on mobile with count + actions:

```heex
<div
  :if={@selection_mode && MapSet.size(@selected_ids) > 0}
  class="fixed bottom-0 left-0 right-0 z-30 bg-ds-surface-card border-t border-ds-outline-variant/20 px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] flex items-center justify-between lg:static lg:border-t-0 lg:px-0 lg:py-2"
>
  <span class="text-sm font-ds-body text-ds-on-surface">
    {MapSet.size(@selected_ids)} selected
  </span>
  <div class="flex items-center gap-2">
    <button type="button" phx-click="request_delete_photos" class="px-3 py-2 text-sm font-ds-body text-ds-error hover:bg-ds-error/10 rounded-ds-sharp transition-colors">
      Delete
    </button>
  </div>
</div>
```

- [ ] **Step 5: Update the upload modal to be full-screen on mobile**

The current upload modal (lines 170-286) uses `flex items-end sm:items-center`. Update:

```heex
<div class="fixed inset-0 z-50 flex items-end lg:items-center justify-center">
  <%!-- Backdrop --%>
  <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_upload_modal" />
  <%!-- Modal content: full-screen on mobile, constrained on desktop --%>
  <div class="relative w-full max-h-[100dvh] lg:max-w-lg lg:max-h-[80vh] bg-ds-surface-card rounded-t-lg lg:rounded-ds-sharp overflow-hidden flex flex-col">
    <%!-- ... existing upload content ... --%>
  </div>
</div>
```

- [ ] **Step 6: Verify in browser**

Check at mobile (375px) and desktop (1280px):
- Mobile: select visible, upload/layout in bottom sheet, selection bar at bottom
- Desktop: all actions in toolbar, no bottom sheet

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/gallery_live/show.html.heex
git commit -m "feat: mobile-first Gallery Show toolbar with bottom sheet and selection bar"
```

---

## Task 5: Gallery Show — Mobile Lightbox with Swipe & Position Indicator

Restructure the lightbox for mobile: full-screen, swipe navigation, position indicator, no thumbnails.

**Files:**
- Create: `assets/js/swipe.js`
- Modify: `assets/js/app.js`
- Modify: `lib/web/components/photo_gallery.ex` (284 lines)

- [ ] **Step 1: Create the Swipe JS hook**

Create `assets/js/swipe.js`:

```javascript
const Swipe = {
  mounted() {
    this.startX = 0
    this.startY = 0
    this.startTime = 0
    this.tracking = false

    this.el.addEventListener("touchstart", this.handleTouchStart.bind(this), { passive: true })
    this.el.addEventListener("touchmove", this.handleTouchMove.bind(this), { passive: false })
    this.el.addEventListener("touchend", this.handleTouchEnd.bind(this), { passive: true })
  },

  destroyed() {
    // Listeners are cleaned up when element is removed
  },

  handleTouchStart(e) {
    if (e.touches.length !== 1) return
    const touch = e.touches[0]
    this.startX = touch.clientX
    this.startY = touch.clientY
    this.startTime = Date.now()
    this.tracking = true
  },

  handleTouchMove(e) {
    if (!this.tracking || e.touches.length !== 1) return
    const touch = e.touches[0]
    const dx = Math.abs(touch.clientX - this.startX)
    const dy = Math.abs(touch.clientY - this.startY)

    // If horizontal movement is dominant, prevent vertical scroll
    if (dx > dy && dx > 10) {
      e.preventDefault()
    }
  },

  handleTouchEnd(e) {
    if (!this.tracking) return
    this.tracking = false

    const touch = e.changedTouches[0]
    const dx = touch.clientX - this.startX
    const dy = touch.clientY - this.startY
    const elapsed = Date.now() - this.startTime
    const absDx = Math.abs(dx)
    const absDy = Math.abs(dy)

    // Must be primarily horizontal and exceed threshold
    if (absDx < 50 || absDy > absDx * 0.75) return

    // Velocity check: must be fast enough (or far enough)
    const velocity = absDx / elapsed
    if (velocity < 0.3 && absDx < 100) return

    if (dx < 0) {
      this.pushEvent("lightbox_keydown", { key: "ArrowRight" })
    } else {
      this.pushEvent("lightbox_keydown", { key: "ArrowLeft" })
    }
  }
}

export default Swipe
```

- [ ] **Step 2: Register the Swipe hook in app.js**

In `assets/js/app.js`, add the import (after the existing hook imports around line 5-8):

```javascript
import Swipe from "./swipe"
```

Add it to the hooks object in the LiveSocket constructor (around line 53-58):

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, FuzzyFilter, TreeConnector, PhotoTagger, PersonHighlight, Swipe }
})
```

- [ ] **Step 3: Update the lightbox component for mobile**

In `lib/web/components/photo_gallery.ex`, update the `lightbox/1` component (lines 105-283).

The key changes:
- Add `phx-hook="Swipe"` to the image container for touch gesture detection
- Add position indicator ("3 of 47") in the top bar
- Hide thumbnail strip on mobile (`hidden lg:flex`)
- Hide side panel on mobile (already `hidden lg:flex`)
- Disable photo tagging on mobile (conditionally render PhotoTagger hook)
- Add close/info buttons in a mobile-friendly top bar

The top bar should become:
```heex
<div class="shrink-0 flex items-center justify-between px-4 py-3 text-white">
  <%!-- Close button --%>
  <button type="button" phx-click="close_lightbox" class="p-2 hover:bg-white/10 rounded-ds-sharp" aria-label="Close">
    <.icon name="hero-x-mark" class="size-6" />
  </button>

  <%!-- Position indicator: mobile only --%>
  <span :if={@total_photos > 1} class="text-sm text-white/70 font-ds-body lg:hidden">
    {@current_index + 1} of {@total_photos}
  </span>

  <%!-- Desktop: filename --%>
  <span class="hidden lg:block text-sm text-white/70 font-ds-body truncate max-w-xs">{@photo.file.file_name}</span>

  <%!-- Right actions --%>
  <div class="flex items-center gap-1">
    <%!-- Info/comments toggle --%>
    <button type="button" phx-click="toggle_panel" class="p-2 hover:bg-white/10 rounded-ds-sharp" aria-label="Photo info">
      <.icon name="hero-information-circle" class="size-6" />
    </button>
    <%!-- Download --%>
    <a href={photo_url(@photo, :original)} download class="p-2 hover:bg-white/10 rounded-ds-sharp hidden lg:block" aria-label="Download">
      <.icon name="hero-arrow-down-tray" class="size-6" />
    </a>
  </div>
</div>
```

The image area should have `phx-hook="Swipe"`:
```heex
<div class="flex-1 flex items-center justify-center relative min-h-0" id="lightbox-swipe" phx-hook="Swipe">
  <%!-- Navigation arrows: desktop only --%>
  <button :if={@has_prev} type="button" phx-click="lightbox_prev" class="hidden lg:block absolute left-4 ...">
    <.icon name="hero-chevron-left" class="size-8" />
  </button>

  <img src={photo_url(@photo, :large)} class="max-h-full max-w-full object-contain" />

  <button :if={@has_next} type="button" phx-click="lightbox_next" class="hidden lg:block absolute right-4 ...">
    <.icon name="hero-chevron-right" class="size-8" />
  </button>
</div>
```

The thumbnail strip should be hidden on mobile:
```heex
<div class="hidden lg:flex shrink-0 gap-2 overflow-x-auto px-4 py-2">
  <%!-- ... existing thumbnails ... --%>
</div>
```

- [ ] **Step 4: Add required assigns for position indicator**

The lightbox needs `current_index` and `total_photos` assigns. In `lib/web/live/gallery_live/show.ex`, when opening the lightbox (around `handle_event("photo_clicked", ...)` lines 135-141), compute and pass these:

```elixir
# When setting @selected_photo, also compute index
photos = get_gallery_photos(socket)
index = Enum.find_index(photos, &(&1.id == photo_id))
total = length(photos)
```

Pass these to the lightbox component in the template.

- [ ] **Step 5: Update photo_grid responsive breakpoints**

In the `photo_grid/1` component (lines 18-95), update the masonry classes:

Current: `columns-2 sm:columns-3 md:columns-4 lg:columns-5 gap-2`
Keep as-is — this already matches the spec (`columns-2`, `sm:columns-3`, then `md:columns-4 lg:columns-5`).

- [ ] **Step 6: Disable PhotoTagger on mobile**

In the lightbox, conditionally apply the PhotoTagger hook only on desktop. Add a `data-no-tagger` attribute on mobile, or wrap the hook application with a media query check in the JS. Simplest approach: always render the hook but the hook itself can check `window.innerWidth` and skip initialization below a threshold.

In `assets/js/photo_tagger.js`, at the start of `mounted()`:

```javascript
mounted() {
  // Disable on mobile viewports
  if (window.innerWidth < 1024) return;
  // ... rest of existing mounted code
}
```

- [ ] **Step 7: Verify lightbox behavior**

At mobile viewport:
- Swipe left/right navigates photos
- Position indicator shows "X of Y"
- No thumbnail strip
- No photo tagging
- Info button works

At desktop:
- Arrow buttons and keys navigate
- Thumbnail strip visible
- Side panel for people/comments
- Photo tagging works

- [ ] **Step 8: Commit**

```bash
git add assets/js/swipe.js assets/js/app.js assets/js/photo_tagger.js lib/web/components/photo_gallery.ex lib/web/live/gallery_live/show.ex
git commit -m "feat: mobile lightbox with swipe navigation, position indicator, no thumbnails"
```

---

## Task 6: Person Show — Hero Photo Header & Mobile Layout

Restructure Person Show for mobile-first: hero photo with name overlay, vertical content stack.

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex` (763 lines)

- [ ] **Step 1: Read the current person show template**

Read `lib/web/live/person_live/show.html.heex` completely.

- [ ] **Step 2: Restructure the toolbar (lines 1-60)**

Mobile: back arrow + person name (optional, since name is on the hero) + bottom sheet trigger
Desktop: show edit, remove, delete directly

```heex
<:toolbar>
  <div class="flex items-center justify-between px-4 py-2 bg-ds-surface-low sm:px-6 lg:px-8">
    <div class="flex items-center gap-2 min-w-0">
      <.link navigate={back_path(assigns)} class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface" aria-label="Back">
        <.icon name="hero-arrow-left" class="size-5" />
      </.link>
      <%!-- Name in toolbar: desktop only (mobile has it on the hero photo) --%>
      <h1 class="hidden lg:block font-ds-heading font-bold text-lg text-ds-on-surface truncate">
        {@person.given_name} {@person.surname}
      </h1>
    </div>

    <div class="flex items-center gap-1">
      <%!-- Desktop actions --%>
      <div class="hidden lg:flex items-center gap-1">
        <button type="button" phx-click="edit" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface">
          <.icon name="hero-pencil-square" class="size-5" />
        </button>
        <button :if={@from_family} type="button" phx-click="request_remove" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface">
          <.icon name="hero-link-slash" class="size-5" />
        </button>
        <button type="button" phx-click="request_delete" class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface">
          <.icon name="hero-trash" class="size-5" />
        </button>
      </div>

      <%!-- Bottom sheet: mobile only --%>
      <button
        type="button"
        phx-click={toggle_bottom_sheet("person-actions")}
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden"
        aria-label="More actions"
      >
        <.icon name="hero-ellipsis-vertical" class="size-5" />
      </button>
    </div>
  </div>
</:toolbar>
```

- [ ] **Step 3: Add person bottom sheet**

```heex
<.bottom_sheet id="person-actions">
  <.sheet_action icon="hero-pencil-square" label="Edit" phx-click={toggle_bottom_sheet("person-actions") |> JS.push("edit")} />
  <.sheet_action :if={@from_family} icon="hero-link-slash" label="Remove from family" phx-click={toggle_bottom_sheet("person-actions") |> JS.push("request_remove")} />
  <.sheet_action icon="hero-trash" label="Delete person" danger phx-click={toggle_bottom_sheet("person-actions") |> JS.push("request_delete")} />
</.bottom_sheet>
```

- [ ] **Step 4: Add hero photo header (mobile) and side-by-side layout (desktop)**

Replace the current two-column detail view (lines 62-199) with:

```heex
<%!-- Hero photo header: mobile shows overlay name, desktop shows side-by-side --%>
<div class="lg:flex lg:gap-8 lg:px-8 lg:py-6 lg:max-w-4xl lg:mx-auto">
  <%!-- Photo container --%>
  <div class="relative lg:w-64 lg:h-64 lg:shrink-0">
    <%= if @person.photo do %>
      <img
        src={person_photo_url(@person)}
        alt={"Photo of #{@person.given_name}"}
        class="w-full max-h-64 object-cover lg:w-64 lg:h-64 lg:rounded-ds-sharp"
      />
    <% else %>
      <div class="w-full h-48 bg-ds-surface-low flex items-center justify-center lg:w-64 lg:h-64 lg:rounded-ds-sharp">
        <span class="text-4xl font-ds-heading font-bold text-ds-on-surface-variant/30">
          {String.first(@person.given_name || "")}{String.first(@person.surname || "")}
        </span>
      </div>
    <% end %>

    <%!-- Name overlay: mobile only --%>
    <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/50 to-transparent p-4 lg:hidden">
      <h1 class="text-white font-ds-heading text-xl font-bold">
        {@person.given_name} {@person.surname}
      </h1>
    </div>
  </div>

  <%!-- Key facts --%>
  <div class="px-4 py-4 lg:px-0 lg:py-0 lg:flex-1">
    <%!-- Desktop name (not overlaid) --%>
    <h1 class="hidden lg:block font-ds-heading text-2xl font-bold text-ds-on-surface mb-4">
      {@person.given_name} {@person.surname}
    </h1>

    <dl class="flex flex-col gap-2 text-sm font-ds-body">
      <%!-- Birth --%>
      <div :if={@person.birth_date_display} class="flex gap-2">
        <dt class="text-ds-on-surface-variant w-16 shrink-0">Born</dt>
        <dd class="text-ds-on-surface">{@person.birth_date_display}</dd>
      </div>
      <%!-- Death --%>
      <div :if={@person.death_date_display} class="flex gap-2">
        <dt class="text-ds-on-surface-variant w-16 shrink-0">Died</dt>
        <dd class="text-ds-on-surface">{@person.death_date_display}</dd>
      </div>
      <%!-- Gender --%>
      <div :if={@person.gender} class="flex gap-2">
        <dt class="text-ds-on-surface-variant w-16 shrink-0">Gender</dt>
        <dd class="text-ds-on-surface capitalize">{@person.gender}</dd>
      </div>
      <%!-- Families --%>
      <div :if={@person.families != []} class="flex gap-2 flex-wrap">
        <dt class="text-ds-on-surface-variant w-16 shrink-0">Families</dt>
        <dd class="flex flex-wrap gap-1">
          <.link
            :for={family <- @person.families}
            navigate={~p"/families/#{family}"}
            class="px-2 py-0.5 bg-ds-surface-high rounded-ds-sharp text-xs text-ds-on-surface hover:bg-ds-surface-highest transition-colors"
          >
            {family.name}
          </.link>
        </dd>
      </div>
      <%!-- Alternate names --%>
      <div :if={@person.alternate_names && @person.alternate_names != ""} class="flex gap-2 flex-wrap">
        <dt class="text-ds-on-surface-variant w-16 shrink-0">Also</dt>
        <dd class="flex flex-wrap gap-1">
          <span
            :for={name <- String.split(@person.alternate_names, "\n", trim: true)}
            class="px-2 py-0.5 bg-ds-surface-low rounded-ds-sharp text-xs text-ds-on-surface-variant"
          >
            {name}
          </span>
        </dd>
      </div>
    </dl>
  </div>
</div>
```

Note: The exact field names (`birth_date_display`, `death_date_display`, `families`, etc.) must be verified against the actual assigns in `show.ex`. Read the existing template to match field names exactly.

- [ ] **Step 5: Restructure relationships section**

Update the relationships grid (lines 202-496) to be mobile-first:

```heex
<div class="px-4 py-6 sm:px-6 lg:px-8 lg:max-w-4xl lg:mx-auto">
  <h2 class="font-ds-heading font-bold text-lg text-ds-on-surface mb-4">Relationships</h2>

  <div class="flex flex-col gap-4 lg:grid lg:grid-cols-2 lg:gap-8">
    <%!-- Spouses & Children --%>
    <div class="bg-ds-surface-card rounded-ds-sharp p-4">
      <h3 class="font-ds-heading font-bold text-sm text-ds-on-surface-variant mb-3">Partners & Children</h3>
      <%!-- ... existing partner groups, but using mobile-friendly person rows ... --%>
    </div>

    <%!-- Parents & Siblings --%>
    <div class="bg-ds-surface-card rounded-ds-sharp p-4">
      <h3 class="font-ds-heading font-bold text-sm text-ds-on-surface-variant mb-3">Parents & Siblings</h3>
      <%!-- ... existing parent/sibling groups ... --%>
    </div>
  </div>

  <%!-- Add relationship button --%>
  <button type="button" phx-click="add_relationship" class="mt-4 w-full py-3 text-sm font-ds-body text-ds-on-surface-variant border border-dashed border-ds-outline-variant/40 rounded-ds-sharp hover:bg-ds-surface-high transition-colors">
    + Add relationship
  </button>
</div>
```

Within each relationship card, person entries should use a consistent row layout:
```heex
<.link navigate={person_path(person)} class="flex items-center gap-3 py-2 hover:bg-ds-surface-high rounded-ds-sharp px-2 transition-colors">
  <div class="w-8 h-8 rounded-full bg-ds-surface-high flex items-center justify-center shrink-0 overflow-hidden">
    <%!-- Photo or placeholder icon --%>
    <.icon :if={!person.photo} name="hero-user" class="size-4 text-ds-on-surface-variant" />
  </div>
  <span class="text-sm font-ds-body text-ds-on-surface">{person.given_name} {person.surname}</span>
</.link>
```

- [ ] **Step 6: Update tagged photos grid**

Update the photos section (lines 499-513) with responsive breakpoints:

```heex
<div :if={@person_photos != []} class="px-4 py-6 sm:px-6 lg:px-8 lg:max-w-4xl lg:mx-auto">
  <h2 class="font-ds-heading font-bold text-lg text-ds-on-surface mb-4">Photos</h2>
  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-2">
    <%!-- ... photo items ... --%>
  </div>
</div>
```

- [ ] **Step 7: Update modals to be full-screen on mobile**

Apply the same modal pattern as Family Show (bottom sheet on mobile, centered on desktop) to:
- Remove from family modal (lines 526-556)
- Delete person modal (lines 558-588)
- Add relationship modal (lines 590-612)
- Edit relationship modal (lines 614-762)

- [ ] **Step 8: Verify in browser**

At mobile (375px):
- Hero photo fills width, name overlaid at bottom with gradient
- Key facts below in compact vertical list
- Relationships as stacked cards
- Bottom sheet for actions

At desktop (1280px):
- Photo on left, name + facts beside it
- Relationships in two-column grid
- Actions in toolbar

- [ ] **Step 9: Commit**

```bash
git add lib/web/live/person_live/show.html.heex
git commit -m "feat: mobile-first Person Show with hero photo, name overlay, and stacked layout"
```

---

## Task 7: Login Page — Mobile-First Full-Screen Form

Restructure the login page for mobile-first with logo, large inputs, and full-width submit.

**Files:**
- Modify: `lib/web/live/account_live/login.ex` (77 lines)

- [ ] **Step 1: Read the current login page**

Read `lib/web/live/account_live/login.ex` completely.

- [ ] **Step 2: Rewrite the render function**

The current page already has `max-w-sm` centered. Update it to be mobile-first:

```elixir
def render(assigns) do
  ~H"""
  <div class="flex flex-col items-center justify-center min-h-[100svh] px-6 bg-ds-surface">
    <div class="w-full max-w-sm">
      <%!-- Logo --%>
      <div class="flex flex-col items-center pt-16 pb-8 lg:pt-8">
        <img src={~p"/images/logo.svg"} alt="Ancestry" class="w-9 h-9 mb-3" />
        <h1 class="font-ds-heading font-bold text-2xl text-ds-on-surface">Ancestry</h1>
      </div>

      <%!-- Form --%>
      <.form
        for={@form}
        id="login_form"
        action={~p"/accounts/log-in"}
        phx-change="validate"
        phx-submit="submit_password"
        phx-trigger-action={@trigger_submit}
      >
        <div class="flex flex-col gap-4">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
            autocomplete="username"
            class="w-full px-4 py-3 bg-ds-surface-card border border-ds-outline-variant/20 rounded-ds-sharp text-base font-ds-body text-ds-on-surface placeholder:text-ds-on-surface-variant/50 focus:border-ds-primary focus:ring-1 focus:ring-ds-primary"
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            required
            autocomplete="current-password"
            class="w-full px-4 py-3 bg-ds-surface-card border border-ds-outline-variant/20 rounded-ds-sharp text-base font-ds-body text-ds-on-surface placeholder:text-ds-on-surface-variant/50 focus:border-ds-primary focus:ring-1 focus:ring-ds-primary"
          />

          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />

          <button
            type="submit"
            class="w-full py-3 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary font-ds-heading font-bold text-sm rounded-ds-sharp transition-all hover:brightness-110 focus:ring-2 focus:ring-ds-primary focus:ring-offset-2"
          >
            Log in
          </button>
        </div>
      </.form>

      <div class="mt-6 text-center">
        <.link
          navigate={~p"/accounts/reset-password"}
          class="text-sm font-ds-body text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
        >
          Forgot your password?
        </.link>
      </div>
    </div>
  </div>
  """
end
```

Note: The login page may not use `<Layouts.app>` wrapper — check if it renders outside the app layout (common for auth pages). If it does use a layout, the `min-h-[100svh]` might need to account for the header. Adjust accordingly.

- [ ] **Step 3: Verify the logo exists**

Check if `priv/static/images/logo.svg` exists. If not, use the existing logo reference from `layouts.ex`. The current layout uses a logo at size 36x36.

- [ ] **Step 4: Verify in browser**

Navigate to the login page:
- Mobile: form fills viewport, large inputs, full-width button
- Desktop: same form, constrained width, centered

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/account_live/login.ex
git commit -m "feat: mobile-first login page with large inputs and centered form"
```

---

## Task 8: Responsive Header & Layout Adjustments

Update the app-level header/layout for mobile friendliness.

**Files:**
- Modify: `lib/web/components/layouts.ex` (196 lines)

- [ ] **Step 1: Read the current layouts.ex**

Read `lib/web/components/layouts.ex` completely.

- [ ] **Step 2: Update the header for mobile**

The header currently shows logo + nav links + settings + logout. On mobile, condense to:
- Logo + app name always visible
- Nav links: hide non-essential items on mobile, show on `sm:` or `lg:`
- Settings/logout: move to a compact area or keep if space allows

Ensure all header elements have 44px minimum tap targets.

- [ ] **Step 3: Ensure toolbar slot works with new sticky behavior**

The toolbar slot is already `sticky z-1 top-0`. Verify it doesn't conflict with the drawer (z-50) or bottom sheet (z-50) z-indices.

- [ ] **Step 4: Verify across all pages**

Navigate through multiple pages at mobile viewport:
- Header doesn't overflow horizontally
- Toolbar is sticky and doesn't conflict with overlays
- Flash messages appear correctly above all content

- [ ] **Step 5: Commit**

```bash
git add lib/web/components/layouts.ex
git commit -m "feat: responsive header with mobile-friendly navigation"
```

---

## Task 9: Cross-Page Verification & Polish

Final verification pass across all four priority pages at multiple viewports.

**Files:**
- May touch any of the modified files for fixes

- [ ] **Step 1: Test at 375px (iPhone SE)**

Navigate through the complete flow:
1. Login → Family index → Family show (tree)
2. Open drawer → search people → focus person in tree
3. Open drawer → tap gallery → Gallery show
4. View photos → open lightbox → swipe through photos
5. Back → tap person in tree → Person show
6. View hero photo, facts, relationships, tagged photos
7. Open bottom sheet → edit person
8. Navigate back to family show

Check for:
- No horizontal overflow on any page
- All tap targets at least 44px
- Text readable without zoom
- Modals/overlays fill screen properly
- Transitions smooth (200ms)

- [ ] **Step 2: Test at 768px (iPad)**

Same flow. Check:
- Intermediate breakpoints work (sm: and md: grids)
- Photo grids use 3 columns
- Modals use bottom-sheet on this size (since it's below lg:)

- [ ] **Step 3: Test at 1280px (Desktop)**

Same flow. Check:
- Side panel inline on family show
- All toolbar actions visible (no bottom sheets)
- Lightbox has side panel and thumbnails
- Person show has side-by-side layout
- Modals centered, constrained width

- [ ] **Step 4: Fix any issues found**

Apply targeted fixes for any layout, overflow, or interaction issues found during testing.

- [ ] **Step 5: Run precommit checks**

Run: `mix precommit`
Expected: Clean compilation, formatting, all tests pass.

- [ ] **Step 6: Fix any test failures**

If existing user flow tests fail due to changed markup (e.g., button text changes, different DOM structure), update the tests to match the new mobile-first markup. The test assertions should test the same user flows but with updated selectors.

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "fix: cross-page verification fixes and test updates for mobile-first refactor"
```

---

## Task 10: Update COMPONENTS.jsonl with Implementation Notes

After all implementation is complete, update COMPONENTS.jsonl with any decisions made during implementation that weren't in the original spec.

**Files:**
- Modify: `COMPONENTS.jsonl`

- [ ] **Step 1: Review what was actually built vs. what was spec'd**

Read through the implemented code and compare with COMPONENTS.jsonl entries. Add any new decisions or update existing ones that changed during implementation.

- [ ] **Step 2: Commit**

```bash
git add COMPONENTS.jsonl
git commit -m "docs: update COMPONENTS.jsonl with implementation decisions"
```
