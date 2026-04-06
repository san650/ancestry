# Mobile-First Phase 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the mobile-first refactor by adding a unified navigation drawer, compact tree person cards, converting remaining daisyUI pages to the design system, and applying cross-cutting mobile fixes (titles, padding, modals).

**Architecture:** The biggest structural change is replacing the top header bar and per-page bottom sheets with a single unified navigation drawer in `layouts.ex`. This drawer renders on every page and contains global nav (orgs, settings, logout) plus page-specific actions and panels passed via slots. The back arrow moves from the toolbar to a floating action button on mobile. Each remaining page gets converted to design system tokens and mobile-first patterns.

**Tech Stack:** Phoenix LiveView 1.0, Tailwind CSS v4 (mobile-first), Phoenix.LiveView.JS for client-side interactions. No new JS hooks needed.

**Validation:** The running app at `http://localhost:4000/` (user: `san650@gmail.com`, password: `012345678912`) should be checked after each task to verify the UI renders correctly on both mobile (375px width) and desktop viewports.

**Key references:**
- Spec: `docs/plans/2026-04-06-mobile-first-phase2-design.md`
- Phase 1 spec: `docs/plans/2026-04-06-mobile-first-design-spec.md`
- Design rules: `DESIGN.md`
- Component decisions: `COMPONENTS.jsonl`

---

## File Map

### New files
- `lib/web/components/nav_drawer.ex` — Unified navigation drawer component (global nav + page actions + page panel slots)

### Modified files
- `lib/web/components/layouts.ex` — Remove header bar on mobile, add hamburger + nav drawer + floating back FAB
- `lib/web/components/mobile.ex` — Keep existing components but they'll be used less on mobile (bottom_sheet still useful for non-action sheets)
- `lib/web/live/family_live/person_card_component.ex` — Compact overlay variant for mobile
- `lib/web/live/family_live/show.html.heex` — Replace right-side drawer with nav drawer integration, pass page actions + panel as slots
- `lib/web/live/family_live/show.ex` — Remove bottom sheet toggle, wire up nav drawer actions
- `lib/web/live/gallery_live/show.html.heex` — Nav drawer integration, remove bottom sheet
- `lib/web/live/person_live/show.html.heex` — Nav drawer integration, remove bottom sheet
- `lib/web/live/organization_live/index.html.heex` — Title fix, better cards, bottom-sheet modal
- `lib/web/live/family_live/index.html.heex` — Title fix, hover-only delete fix, bottom-sheet modal
- `lib/web/live/family_live/new.html.heex` — Title fix, padding fix
- `lib/web/live/person_live/new.html.heex` — Title fix, padding fix
- `lib/web/live/gallery_live/index.html.heex` — Full daisyUI → design system conversion
- `lib/web/live/person_live/index.html.heex` — Full daisyUI → design system conversion (if still routed; may be dead code — check router first)
- `lib/web/live/org_people_live/index.html.heex` — Mobile table column hiding
- `lib/web/live/people_live/index.html.heex` — Title fix
- `lib/web/live/kinship_live.html.heex` — Title fix, mobile branch stacking
- `lib/web/live/account_live/settings.ex` — Title fix
- `lib/web/live/account_live/login.ex` — Title fix
- `lib/web/live/account_live/confirmation.ex` — Title fix

### Possibly dead files (no route in router — verify before converting)
- `lib/web/live/gallery_live/index.html.heex` — No route to `GalleryLive.Index` in `router.ex`. May be accessed via navigation from other pages or may be dead code.
- `lib/web/live/person_live/index.html.heex` — No route to `PersonLive.Index` in `router.ex`. May be dead code replaced by `PeopleLive.Index`.

---

## Task 1: Unified Navigation Drawer Component

Build the new `NavDrawer` component that replaces the header bar and per-page bottom sheets on mobile.

**Files:**
- Create: `lib/web/components/nav_drawer.ex`

- [ ] **Step 1: Create the nav drawer component module**

Create `lib/web/components/nav_drawer.ex`:

```elixir
defmodule Web.Components.NavDrawer do
  @moduledoc """
  Unified navigation drawer for mobile. Slides from the left.
  Contains page actions (slot), page panel (slot), org list, and account links.
  On desktop (lg:), the drawer is hidden — header bar and toolbar buttons remain.
  """
  use Phoenix.Component

  import Web.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, default: "nav-drawer"
  attr :current_scope, :map, default: nil
  slot :page_actions, doc: "Page-specific action items (edit, delete, etc.)"
  slot :page_panel, doc: "Page-specific panel content (e.g., people search + gallery list on Family Show)"
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
      aria-label="Navigation"
    >
      <%!-- Header: logo + close --%>
      <div class="flex items-center justify-between p-4 border-b border-ds-outline-variant/20">
        <a href="/" class="flex items-center gap-2">
          <img src="/images/logo.png" width="32" class="rounded-ds-sharp" />
          <span class="font-ds-heading font-bold text-ds-on-surface">Ancestry</span>
        </a>
        <button
          type="button"
          phx-click={toggle_nav_drawer(@id)}
          class="p-2 rounded-ds-sharp text-ds-on-surface-variant hover:bg-ds-surface-high min-w-[44px] min-h-[44px] flex items-center justify-center"
          aria-label="Close menu"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <%!-- Page actions section --%>
      <%= if @page_actions != [] do %>
        <div class="px-4 pt-4 pb-2">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-ds-on-surface-variant px-2 pb-2">
            Page Actions
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
            Organizations
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
            <span class="font-ds-body text-sm">Settings</span>
          </.link>
          <.link
            href="/accounts/log-out"
            method="delete"
            class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-5 shrink-0 text-ds-on-surface-variant" />
            <span class="font-ds-body text-sm">Log out</span>
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
```

- [ ] **Step 2: Import the nav drawer in web.ex**

In `lib/web.ex`, inside `html_helpers/0`, add after the `import Web.Components.Mobile` line:

```elixir
import Web.Components.NavDrawer
```

- [ ] **Step 3: Verify app compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compiles without errors.

- [ ] **Step 4: Commit**

```bash
git add lib/web/components/nav_drawer.ex lib/web.ex
git commit -m "feat: add unified navigation drawer component"
```

---

## Task 2: Integrate Nav Drawer into Layouts

Replace the mobile header bar with the hamburger button and nav drawer. Add the floating back FAB.

**Files:**
- Modify: `lib/web/components/layouts.ex`

- [ ] **Step 1: Add org list loading**

The layout needs to display the user's organizations in the nav drawer. Since `layouts.ex` doesn't have access to the database, the org list needs to be loaded in the live session's `on_mount`. Check if `Web.EnsureOrganization` or `Web.AccountAuth` already loads orgs. If not, you'll need to pass the org list as an assign.

Check what `Web.EnsureOrganization` does:

```bash
grep -n "assign\|organizations" lib/web/live/ensure_organization.ex
```

If orgs aren't available, add a `nav_organizations` assign in the `on_mount` callback that fetches the user's organizations. If this is too complex, the nav drawer's org section can use a simple link to `/org` instead of listing all orgs inline.

**Simpler approach (recommended):** Instead of listing orgs inline, link to the `/org` organizations page:

```elixir
<.link
  href="/org"
  class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
>
  <.icon name="hero-building-office-2" class="size-5 shrink-0 text-ds-on-surface-variant" />
  <span class="font-ds-body text-sm">Organizations</span>
</.link>
```

- [ ] **Step 2: Modify the app layout in layouts.ex**

Replace the `<header>` section and add the nav drawer and FAB. The header should be hidden on mobile (`hidden lg:flex`) and the hamburger should only show on mobile (`lg:hidden`).

In `lib/web/components/layouts.ex`, replace the `app/1` function's `~H` template with:

```heex
<div class="min-h-screen">
  <%!-- Desktop header: hidden on mobile --%>
  <header class="hidden lg:flex items-center px-4 sm:px-6 lg:px-8 py-2">
    <div class="flex-1">
      <a href="/" class="flex-1 flex w-fit items-center gap-2">
        <img src={~p"/images/logo.png"} width="36" />
        <span class="text-sm font-ds-body font-semibold text-ds-on-surface">Ancestry</span>
      </a>
    </div>
    <div class="flex-none">
      <ul class="flex flex-row px-1 items-center gap-2 lg:gap-4 font-ds-body text-sm text-ds-on-surface-variant">
        <%= if @current_scope && @current_scope.account do %>
          <%= if @current_scope.organization do %>
            <li>
              <.link
                navigate={~p"/org/#{@current_scope.organization.id}"}
                class="font-medium text-ds-on-surface"
              >
                {@current_scope.organization.name}
              </.link>
            </li>
          <% else %>
            <li>
              <.link href={~p"/org"}>Organizations</.link>
            </li>
          <% end %>
          <li class="text-ds-outline-variant">|</li>
          <li>{@current_scope.account.email}</li>
          <li>
            <.link
              href={~p"/accounts/settings"}
              class="p-2 hover:text-ds-on-surface transition-colors"
            >
              Settings
            </.link>
          </li>
          <li>
            <.link
              href={~p"/accounts/log-out"}
              method="delete"
              class="p-2 hover:text-ds-on-surface transition-colors"
            >
              Log out
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
  </header>

  <%= if @toolbar != [] do %>
    <div
      id="toolbar"
      class="sticky z-1 top-0 bg-ds-surface-low"
    >
      {render_slot(@toolbar)}
    </div>
  <% end %>

  <main class="min-h-100">
    {render_slot(@inner_block)}
  </main>
  <.flash_group flash={@flash} />
</div>
```

Note: The nav drawer itself and the hamburger trigger are NOT in layouts.ex — they are rendered by each page's template (or by a shared toolbar component). This keeps the layout simple and lets each page control its drawer content via slots.

- [ ] **Step 3: Verify app compiles and desktop header still works**

Run: `mix compile --warnings-as-errors`
Then check `http://localhost:4000` on a desktop viewport — header should be visible. On a mobile viewport (375px), header should be hidden.

- [ ] **Step 4: Commit**

```bash
git add lib/web/components/layouts.ex
git commit -m "feat: hide header on mobile, desktop header preserved"
```

---

## Task 3: Add Hamburger + Nav Drawer + FAB to Family Show

Wire up the unified nav drawer on the first page: Family Show. This establishes the pattern for all other pages.

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`
- Modify: `lib/web/live/family_live/show.ex`

- [ ] **Step 1: Update the toolbar in show.html.heex**

Replace the current toolbar's right-side drawer toggle and bottom sheet trigger with the hamburger on the left. Remove the back arrow from the toolbar on mobile. Keep desktop actions unchanged.

Replace the toolbar section (lines 2-105) with:

```heex
<:toolbar>
  <div class="flex items-center justify-between px-4 py-2 bg-ds-surface-low sm:px-6 lg:px-8">
    <%!-- Left: hamburger (mobile) + back (desktop) + title --%>
    <div class="flex items-center gap-2 min-w-0">
      <%!-- Hamburger: mobile only --%>
      <button
        type="button"
        phx-click={toggle_nav_drawer()}
        class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
        aria-label="Open menu"
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>
      <%!-- Back arrow: desktop only --%>
      <.link
        navigate={~p"/org/#{@current_scope.organization.id}"}
        class="hidden lg:flex p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface"
        aria-label="Back to families"
        {test_id("family-back-btn")}
      >
        <.icon name="hero-arrow-left" class="size-5" />
      </.link>
      <h1
        class="font-ds-heading font-bold text-lg text-ds-on-surface truncate"
        {test_id("family-name")}
      >
        {@family.name}
      </h1>
    </div>

    <%!-- Right: desktop-only actions --%>
    <div class="hidden lg:flex items-center gap-1">
      <.link
        navigate={
          if(@focus_person,
            do:
              ~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/kinship?person_a=#{@focus_person.id}",
            else: ~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/kinship"
          )
        }
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
        aria-label="Kinship calculator"
        id="kinship-btn"
        {test_id("family-kinship-btn")}
      >
        <.icon name="hero-arrows-right-left" class="size-5" />
      </.link>
      <button
        type="button"
        id="edit-family-btn"
        phx-click="edit"
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
        aria-label="Edit family"
        {test_id("family-edit-btn")}
      >
        <.icon name="hero-pencil-square" class="size-5" />
      </button>
      <button
        type="button"
        id="delete-family-btn"
        phx-click="request_delete"
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
        aria-label="Delete family"
        {test_id("family-delete-btn")}
      >
        <.icon name="hero-trash" class="size-5" />
      </button>
      <.link
        navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/people"}
        class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
        aria-label="Manage people"
        id="manage-people-btn"
        {test_id("family-manage-people-btn")}
      >
        <.icon name="hero-user-group" class="size-5" />
      </.link>
      <%= if @people != [] do %>
        <button
          type="button"
          id="create-subfamily-btn"
          phx-click="open_create_subfamily"
          class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
          aria-label="Create subfamily"
          {test_id("family-create-subfamily-btn")}
        >
          <.icon name="hero-square-2-stack" class="size-5" />
        </button>
      <% end %>
    </div>
  </div>
</:toolbar>
```

- [ ] **Step 2: Replace the bottom sheet and right-side drawer with the nav drawer**

Remove the `<.bottom_sheet id="family-actions">` block (lines 108-134).

Remove the `<.drawer id="family-drawer">` block that wraps the side panel (lines 207-218).

Add the nav drawer after the toolbar slot, before the grid:

```heex
<%!-- Unified nav drawer: mobile only --%>
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action
      icon="hero-pencil-square"
      label="Edit family"
      phx-click={toggle_nav_drawer() |> JS.push("edit")}
    />
    <.nav_action
      icon="hero-arrows-right-left"
      label="Kinship calculator"
      phx-click={
        toggle_nav_drawer()
        |> JS.navigate(
          if(@focus_person,
            do:
              ~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/kinship?person_a=#{@focus_person.id}",
            else: ~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/kinship"
          )
        )
      }
    />
    <.nav_action
      icon="hero-trash"
      label="Delete family"
      danger
      phx-click={toggle_nav_drawer() |> JS.push("request_delete")}
    />
  </:page_actions>
  <:page_panel>
    <.live_component
      module={Web.FamilyLive.SidePanelComponent}
      id="side-panel"
      galleries={@galleries}
      people={@people}
      family_id={@family.id}
      organization={@current_scope.organization}
      focus_person_id={@focus_person && @focus_person.id}
      metrics={@metrics}
    />
  </:page_panel>
  <%!-- Inner block: org navigation --%>
  <.link
    href={~p"/org"}
    class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
  >
    <.icon name="hero-building-office-2" class="size-5 shrink-0 text-ds-on-surface-variant" />
    <span class="font-ds-body text-sm">Organizations</span>
  </.link>
</.nav_drawer>
```

- [ ] **Step 3: Add floating back FAB**

After the nav drawer, add:

```heex
<%!-- Floating back button: mobile only --%>
<.link
  navigate={~p"/org/#{@current_scope.organization.id}"}
  class="fixed bottom-4 left-4 z-30 bg-ds-surface-card shadow-ds-ambient rounded-full min-w-[44px] min-h-[44px] flex items-center justify-center lg:hidden"
  aria-label="Back to families"
  {test_id("family-back-fab")}
>
  <.icon name="hero-arrow-left" class="size-5 text-ds-on-surface" />
</.link>
```

- [ ] **Step 4: Update the grid layout**

The grid no longer needs the drawer column on mobile (it's in the nav drawer now). Keep the desktop inline panel.

Change the grid (line 136) from:
```heex
<div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] gap-0 lg:gap-4 overflow-x-hidden">
```

The side panel for desktop needs to remain inline. Add it back as a desktop-only element inside the grid:

```heex
<div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] gap-0 lg:gap-4 overflow-x-hidden">
  <%!-- Tree Canvas --%>
  <div id="tree-canvas" class="relative overflow-auto hide-scrollbar p-6 order-last lg:order-first min-h-[60vh]" phx-hook="TreeConnector">
    <%!-- ... existing tree content unchanged ... --%>
  </div>

  <%!-- Desktop-only side panel (inline) --%>
  <div class="hidden lg:block">
    <.live_component
      module={Web.FamilyLive.SidePanelComponent}
      id="side-panel-desktop"
      galleries={@galleries}
      people={@people}
      family_id={@family.id}
      organization={@current_scope.organization}
      focus_person_id={@focus_person && @focus_person.id}
      metrics={@metrics}
    />
  </div>
</div>
```

Note: This renders the SidePanelComponent twice — once in the nav drawer (mobile) and once inline (desktop). The `id` must be different (`side-panel` vs `side-panel-desktop`).

- [ ] **Step 5: Remove the old drawer toggle import**

In `lib/web/live/family_live/show.ex`, if there are any references to `toggle_drawer("family-drawer")` in event handlers, remove them. The show.ex file already imports `Web.Components.Mobile` via `web.ex`, so `toggle_nav_drawer/0` from `Web.Components.NavDrawer` will be available automatically.

- [ ] **Step 6: Verify Family Show works on mobile and desktop**

Run the app and check:
- Mobile (375px): hamburger on left, no back arrow in toolbar, no meatball, drawer slides from left with page actions + side panel + orgs + logout. FAB back button at bottom-left.
- Desktop: header bar visible, toolbar has back arrow + action icons, inline side panel on right. No hamburger, no FAB.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/family_live/show.html.heex lib/web/live/family_live/show.ex
git commit -m "feat: unified nav drawer on Family Show, floating back FAB"
```

---

## Task 4: Compact Person Card for Mobile TreeView

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex`

- [ ] **Step 1: Update the person_card component**

Replace the `person_card/1` function to render a compact overlay variant on mobile and the current layout on desktop.

In `lib/web/live/family_live/person_card_component.ex`, replace the `person_card/1` function (lines 14-58):

```elixir
def person_card(assigns) do
  ~H"""
  <button
    type="button"
    data-person-id={@person.id}
    id={if(@focused, do: "focus-person-card", else: "person-card-#{@person.id}")}
    phx-click="focus_person"
    phx-value-id={@person.id}
    class={[
      "relative flex flex-col items-center text-center rounded-ds-sharp transition-all duration-150 group",
      "bg-ds-surface-card",
      gender_border_class(@person.gender),
      if(@focused, do: "ring-2 ring-ds-primary scale-105 z-1", else: "hover:bg-ds-surface-high"),
      "focus-visible:outline-2 focus-visible:outline-ds-primary focus-visible:outline-offset-2",
      "w-[72px] lg:w-28 lg:p-2"
    ]}
    aria-label={"#{Person.display_name(@person)}"}
  >
    <%!-- Mobile: square photo with name overlay --%>
    <div class="relative w-full h-[72px] lg:hidden overflow-hidden rounded-b-ds-sharp">
      <%= if @person.photo && @person.photo_status == "processed" do %>
        <img
          src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
          alt={Person.display_name(@person)}
          class="w-full h-full object-cover"
        />
      <% else %>
        <div class="w-full h-full bg-ds-surface-low flex items-center justify-center">
          <.icon name="hero-user" class={["w-8 h-8", gender_icon_class(@person.gender)]} />
        </div>
      <% end %>
      <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent px-1 pt-4 pb-1 text-center">
        <p class="text-[9px] font-semibold text-white leading-tight line-clamp-2">
          {Person.display_name(@person)}
        </p>
      </div>
    </div>

    <%!-- Desktop: original layout with circular photo + name + dates --%>
    <div class="hidden lg:flex lg:flex-col lg:items-center">
      <div class="w-14 h-14 rounded-full bg-ds-primary/10 flex items-center justify-center overflow-hidden mb-1 group-hover:ring-2 group-hover:ring-ds-primary/50 transition-all">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class={["w-7 h-7", gender_icon_class(@person.gender)]} />
        <% end %>
      </div>
      <p class="text-xs font-medium text-ds-on-surface w-full group-hover:text-ds-primary transition-colors line-clamp-2 leading-tight min-h-[2lh]">
        {Person.display_name(@person)}
      </p>
      <p class="text-[10px] text-ds-on-surface-variant">
        <%= if @person.birth_year do %>
          {format_life_span(@person)}
        <% else %>
          &nbsp;
        <% end %>
      </p>
    </div>

    <%= if @has_more do %>
      <div class="mt-1 text-ds-on-surface-variant/50 hidden lg:block" title="Has more descendants">
        <.icon name="hero-chevron-down" class="w-3 h-3" />
      </div>
    <% end %>
  </button>
  """
end
```

- [ ] **Step 2: Update the placeholder_card component**

Scale down on mobile:

```elixir
def placeholder_card(assigns) do
  ~H"""
  <button
    phx-click="add_relationship"
    phx-value-type={@type}
    phx-value-person-id={@person_id}
    class="flex flex-col items-center text-center rounded-ds-sharp border border-dashed border-ds-on-surface-variant/50 hover:border-ds-primary/50 hover:bg-ds-primary/5 transition-all cursor-pointer group w-[72px] h-[72px] lg:w-28 lg:h-auto lg:p-2 justify-center"
  >
    <div class="w-8 h-8 lg:w-14 lg:h-14 rounded-full bg-ds-on-surface/5 flex items-center justify-center lg:mb-1 group-hover:bg-ds-primary/10 transition-colors">
      <.icon
        name="hero-plus"
        class="w-4 h-4 lg:w-6 lg:h-6 text-ds-on-surface-variant/50 group-hover:text-ds-primary transition-colors"
      />
    </div>
    <p class="text-[9px] lg:text-xs text-ds-on-surface-variant group-hover:text-ds-primary transition-colors">
      {placeholder_label(@type)}
    </p>
  </button>
  """
end
```

- [ ] **Step 3: Scale down gaps in subtrees**

In the `family_subtree/1` function, change the outer gap:
```
"flex items-start justify-center gap-8"
```
to:
```
"flex items-start justify-center gap-4 lg:gap-8"
```

In the `subtree_children/1` function, change:
```
"flex items-start gap-6"
```
to:
```
"flex items-start gap-3 lg:gap-6"
```

In the `ancestor_subtree/1` function, change:
```
"flex items-end justify-center gap-8 mb-5"
```
to:
```
"flex items-end justify-center gap-4 lg:gap-8 mb-3 lg:mb-5"
```

- [ ] **Step 4: Verify tree looks compact on mobile, normal on desktop**

Check `http://localhost:4000` on Family Show with a tree loaded. Mobile (375px): compact 72px cards with overlay names, tighter gaps. Desktop: original layout.

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex
git commit -m "feat: compact person card with photo overlay on mobile"
```

---

## Task 5: Nav Drawer on Gallery Show and Person Show

Apply the same nav drawer pattern to the other already-converted pages.

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex`
- Modify: `lib/web/live/person_live/show.html.heex`

- [ ] **Step 1: Update Gallery Show toolbar**

Same pattern as Family Show:
- Replace toolbar: hamburger on left (mobile only), back arrow (desktop only), title. Remove bottom sheet trigger.
- Remove the `<.bottom_sheet id="gallery-actions">` block.
- Add `<.nav_drawer>` with page actions: Upload photos, Toggle layout. Plus the org link and account section.
- Add floating back FAB pointing to family page.
- Keep desktop toolbar actions (select, upload, layout toggle) unchanged.

- [ ] **Step 2: Update Person Show toolbar**

Same pattern:
- Replace toolbar: hamburger on left (mobile only), back arrow (desktop only, conditional on `@from_family`/`@from_org`), title (desktop only — mobile already has it on hero).
- Remove the `<.bottom_sheet id="person-actions">` block.
- Add `<.nav_drawer>` with page actions: Edit, Remove from family (if `@from_family`), Delete (danger).
- Add floating back FAB with the correct back path (conditional).

- [ ] **Step 3: Verify both pages**

Check Gallery Show and Person Show on mobile and desktop.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/gallery_live/show.html.heex lib/web/live/person_live/show.html.heex
git commit -m "feat: unified nav drawer on Gallery Show and Person Show"
```

---

## Task 6: Nav Drawer on Remaining Pages

Add the hamburger + nav drawer to all pages that have a toolbar. Pages without page-specific actions just get the global nav sections.

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex`
- Modify: `lib/web/live/family_live/index.html.heex`
- Modify: `lib/web/live/family_live/new.html.heex`
- Modify: `lib/web/live/person_live/new.html.heex`
- Modify: `lib/web/live/people_live/index.html.heex`
- Modify: `lib/web/live/org_people_live/index.html.heex`
- Modify: `lib/web/live/kinship_live.html.heex`

- [ ] **Step 1: Add hamburger + nav drawer to each page's toolbar**

For each page:
1. Add hamburger button on left (mobile only, `lg:hidden`)
2. Change back arrow to desktop only (`hidden lg:flex`)
3. Add `<.nav_drawer>` with appropriate page actions (or empty if none)
4. Add floating back FAB where a back arrow exists
5. Pages that are top-level (Organization Index, Family Index) don't need a back FAB

- [ ] **Step 2: Verify each page**

Check each page on mobile and desktop viewports.

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/organization_live/index.html.heex lib/web/live/family_live/index.html.heex lib/web/live/family_live/new.html.heex lib/web/live/person_live/new.html.heex lib/web/live/people_live/index.html.heex lib/web/live/org_people_live/index.html.heex lib/web/live/kinship_live.html.heex
git commit -m "feat: unified nav drawer on all remaining pages"
```

---

## Task 7: Cross-cutting Title and Padding Fixes

**Files:**
- Modify: All files with `text-2xl` toolbar titles
- Modify: `lib/web/live/family_live/new.html.heex`
- Modify: `lib/web/live/person_live/new.html.heex`

- [ ] **Step 1: Fix all toolbar titles**

Change `text-2xl` to `text-lg` in toolbar `<h1>` elements across all files listed in the grep results. The already-converted pages (Family Show, Gallery Show, Person Show) already use `text-lg`. Fix these:

- `lib/web/live/organization_live/index.html.heex` — `text-2xl font-ds-heading font-extrabold` → `text-lg font-ds-heading font-bold`
- `lib/web/live/family_live/index.html.heex` — same
- `lib/web/live/family_live/new.html.heex` — same
- `lib/web/live/person_live/new.html.heex` — same
- `lib/web/live/person_live/index.html.heex` — `text-2xl font-bold text-base-content` → `text-lg font-ds-heading font-bold text-ds-on-surface`
- `lib/web/live/gallery_live/index.html.heex` — `text-2xl font-bold text-base-content` → `text-lg font-ds-heading font-bold text-ds-on-surface`
- `lib/web/live/org_people_live/index.html.heex` — same pattern
- `lib/web/live/people_live/index.html.heex` — same pattern
- `lib/web/live/kinship_live.html.heex` — same
- `lib/web/live/account_live/settings.ex` — `text-2xl` → `text-lg` (this is a page heading, not a toolbar, but still oversized)
- `lib/web/live/account_live/login.ex` — `text-2xl` → `text-lg`
- `lib/web/live/account_live/confirmation.ex` — `text-2xl` → `text-lg`

Note: `lib/web/live/family_live/side_panel_component.ex` has `text-2xl` for metric numbers — do NOT change those, they are data display, not titles.

- [ ] **Step 2: Fix full-page form padding**

In `lib/web/live/family_live/new.html.heex`, change:
```heex
<div class="max-w-lg mx-auto mt-8">
```
to:
```heex
<div class="max-w-lg mx-auto mt-8 px-4">
```

In `lib/web/live/person_live/new.html.heex`, change:
```heex
<div class="max-w-2xl mx-auto mt-8">
```
to:
```heex
<div class="max-w-2xl mx-auto mt-8 px-4">
```

- [ ] **Step 3: Verify titles and padding on mobile**

Spot-check a few pages on mobile — titles should be smaller, forms should have side padding.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix: smaller toolbar titles and form padding on mobile"
```

---

## Task 8: Organization Index Improvements

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex`

- [ ] **Step 1: Improve org cards**

Add an icon and make the cards more visually distinct:

Replace the org card `<.link>` (lines 30-39) with:

```heex
<.link
  :for={{id, org} <- @streams.organizations}
  id={id}
  navigate={~p"/org/#{org.id}"}
  class="block bg-ds-surface-card rounded-ds-sharp p-5 hover:bg-ds-surface-highest transition-colors"
>
  <div class="flex items-center gap-3">
    <div class="w-10 h-10 rounded-ds-sharp bg-ds-primary/10 flex items-center justify-center flex-shrink-0">
      <.icon name="hero-building-office-2" class="w-5 h-5 text-ds-primary" />
    </div>
    <h2 class="text-base font-ds-heading font-bold text-ds-on-surface tracking-tight truncate">
      {org.name}
    </h2>
  </div>
</.link>
```

- [ ] **Step 2: Make the create modal bottom-sheet on mobile**

Change the modal container (line 47):
```heex
class="fixed inset-0 z-50 flex items-center justify-center"
```
to:
```heex
class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
```

Change the modal dialog (line 63):
```heex
class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient rounded-ds-sharp w-full max-w-md mx-4 p-8"
```
to:
```heex
class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
```

- [ ] **Step 3: Compact the "New Organization" button on mobile**

Change the button (lines 8-13) to be smaller on mobile:

```heex
<button
  phx-click="new_organization"
  class="inline-flex items-center gap-2 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-3 py-2 lg:px-5 lg:py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
  {test_id("org-new-btn")}
>
  <.icon name="hero-plus" class="w-4 h-4" />
  <span class="hidden sm:inline">New Organization</span>
</button>
```

- [ ] **Step 4: Verify and commit**

```bash
git add lib/web/live/organization_live/index.html.heex
git commit -m "feat: improved org cards, mobile bottom-sheet modal, compact button"
```

---

## Task 9: Family Index Fixes

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex`

- [ ] **Step 1: Fix hover-only delete button**

Change the delete button (line 76-83) class from:
```
"absolute top-3 right-3 p-1.5 rounded-ds-sharp text-ds-on-surface-variant/30 hover:text-ds-error hover:bg-ds-error/10 opacity-0 group-hover:opacity-100 transition-all"
```
to:
```
"absolute top-3 right-3 p-1.5 rounded-ds-sharp text-ds-on-surface-variant/30 hover:text-ds-error hover:bg-ds-error/10 lg:opacity-0 lg:group-hover:opacity-100 transition-all"
```

This keeps the delete button always visible on mobile/tablet but hover-reveal on desktop.

- [ ] **Step 2: Make delete modal bottom-sheet on mobile**

Change the modal container (line 95):
```
"fixed inset-0 z-50 flex items-center justify-center"
```
to:
```
"fixed inset-0 z-50 flex items-end lg:items-center justify-center"
```

Change the modal dialog (line 99):
```
"relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient rounded-ds-sharp w-full max-w-md mx-4 p-8"
```
to:
```
"relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
```

- [ ] **Step 3: Verify and commit**

```bash
git add lib/web/live/family_live/index.html.heex
git commit -m "fix: always-visible delete button on mobile, bottom-sheet modal"
```

---

## Task 10: Gallery Index — daisyUI Conversion

**Files:**
- Modify: `lib/web/live/gallery_live/index.html.heex`

- [ ] **Step 1: Convert all daisyUI classes to design system**

Full conversion of `lib/web/live/gallery_live/index.html.heex`. Replace all old classes:

- Toolbar back link: `rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200` → `rounded-ds-sharp text-ds-on-surface-variant hover:text-ds-on-surface hover:bg-ds-surface-highest`
- Title: `text-2xl font-bold text-base-content` → `text-lg font-ds-heading font-bold text-ds-on-surface`
- New Gallery button: `btn btn-primary` → `inline-flex items-center gap-2 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-5 py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity`
- Gallery cards: `group relative card bg-base-100 shadow-sm border border-base-200 hover:shadow-md transition-all duration-200` → `group relative bg-ds-surface-card rounded-ds-sharp hover:bg-ds-surface-highest transition-colors`
- Card icon: `rounded-xl bg-primary/10` → `rounded-ds-sharp bg-ds-primary/10`, `text-primary` → `text-ds-primary`
- Card title: `text-lg font-semibold text-base-content` → `text-lg font-ds-heading font-bold text-ds-on-surface`
- Card date: `text-sm text-base-content/50` → `text-sm text-ds-on-surface-variant`
- Delete button: `rounded-lg text-base-content/30 hover:text-error hover:bg-error/10 opacity-0 group-hover:opacity-100` → `rounded-ds-sharp text-ds-on-surface-variant/30 hover:text-ds-error hover:bg-ds-error/10 lg:opacity-0 lg:group-hover:opacity-100`
- Empty state: `text-base-content/40` → `text-ds-on-surface-variant`
- New gallery modal: `card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8` → `bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8`
- Modal container: `flex items-center justify-center` → `flex items-end lg:items-center justify-center`
- Modal title: `text-xl font-bold text-base-content` → `text-xl font-ds-heading font-bold text-ds-on-surface`
- Submit button: `btn btn-primary flex-1` → `flex-1 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity`
- Cancel button: `btn btn-ghost flex-1` → `flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors`
- Delete modal: same conversions as new gallery modal
- Delete confirm: `btn btn-error flex-1` → `flex-1 bg-ds-error text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:opacity-90 transition-opacity`

- [ ] **Step 2: Add hamburger + nav drawer + back FAB**

Same pattern as other pages. No page-specific actions for gallery index.

- [ ] **Step 3: Verify and commit**

```bash
git add lib/web/live/gallery_live/index.html.heex
git commit -m "feat: convert Gallery Index from daisyUI to design system"
```

---

## Task 11: Person Index — daisyUI Conversion

**Files:**
- Modify: `lib/web/live/person_live/index.html.heex`

- [ ] **Step 1: Check if this page is still routed**

```bash
grep -n "PersonLive.Index" lib/web/router.ex
```

If no route exists, this may be dead code. If dead, skip conversion and optionally delete the files. If it IS routed or navigated to from other pages, proceed with conversion.

- [ ] **Step 2: Convert daisyUI classes (if still in use)**

Same token mapping as Gallery Index. Key changes:
- `btn btn-ghost btn-sm` → `inline-flex items-center gap-1.5 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp px-3 py-1.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors`
- `btn btn-primary btn-sm` → `inline-flex items-center gap-1.5 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-3 py-1.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity`
- `card bg-base-100 shadow-sm border border-base-200 hover:shadow-md` → `bg-ds-surface-card rounded-ds-sharp hover:bg-ds-surface-highest transition-colors`
- All `text-base-content` → `text-ds-on-surface`, `text-base-content/40` → `text-ds-on-surface-variant`
- `bg-primary/10` → `bg-ds-primary/10`, `text-primary` → `text-ds-primary`
- Modal: same bottom-sheet pattern
- `input input-bordered` → design system input styling
- `rounded-lg hover:bg-base-200` → `rounded-ds-sharp hover:bg-ds-surface-highest`
- `btn btn-ghost w-full` → full-width surface button

- [ ] **Step 3: Verify and commit**

```bash
git add lib/web/live/person_live/index.html.heex
git commit -m "feat: convert Person Index from daisyUI to design system"
```

---

## Task 12: Org People Index — Mobile Table

**Files:**
- Modify: `lib/web/live/org_people_live/index.html.heex`

- [ ] **Step 1: Hide table columns on mobile**

The grid currently uses `grid-cols-[auto_auto_auto_auto_auto_auto_1fr]` (edit mode) or `grid-cols-[auto_auto_auto_auto_auto_1fr]` (normal mode). On mobile, show only photo + name.

Change the grid class (lines 103-108):

For non-edit mode:
```
"grid-cols-[auto_1fr] md:grid-cols-[auto_auto_auto_auto_auto_1fr]"
```

For edit mode:
```
"grid-cols-[auto_auto_1fr] md:grid-cols-[auto_auto_auto_auto_auto_auto_1fr]"
```

Add `hidden md:block` (or `hidden md:flex`) to these cells:
- Header: Est. Age, Lifespan, Links, empty actions header
- Row: estimated age div, lifespan div, links div, actions div

The checkbox (edit mode), photo, and name cells remain visible on all sizes.

- [ ] **Step 2: Fix the `indicator` daisyUI class**

The deceased indicator uses `indicator` and `indicator-item` which are daisyUI classes. Replace with Tailwind:

Change the photo cell (lines 167-189):
```heex
<div class="px-3 py-2.5">
  <div class="relative">
    <%= if person.deceased do %>
      <span
        class="absolute -top-1 -right-1 text-[10px] text-ds-on-surface-variant bg-ds-surface-card px-1 rounded-full border border-ds-outline-variant/20 z-10"
        title="Deceased"
      >
        d.
      </span>
    <% end %>
    <div class="w-10 h-10 rounded-full overflow-hidden bg-ds-surface-low flex items-center justify-center">
      <%!-- ... existing photo/icon content ... --%>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Verify table on mobile and desktop**

Mobile: only photo + name visible, compact rows. Desktop: full table with all columns.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/org_people_live/index.html.heex
git commit -m "feat: responsive table columns, hide detail columns on mobile"
```

---

## Task 13: Kinship — Mobile Layout

**Files:**
- Modify: `lib/web/live/kinship_live.html.heex`

- [ ] **Step 1: Stack person selectors vertically on mobile**

Change the selector container (line 21):
```heex
<div class="flex items-start gap-4" {test_id("kinship-selectors")}>
```
to:
```heex
<div class="flex flex-col sm:flex-row items-stretch sm:items-start gap-4" {test_id("kinship-selectors")}>
```

The swap button container (line 37):
```heex
<div class="pt-7">
```
to:
```heex
<div class="flex justify-center sm:pt-7">
```

Also rotate the swap icon on mobile — add a class to rotate the arrows icon 90 degrees on mobile so it points up/down instead of left/right:
```heex
<.icon name="hero-arrows-right-left" class="w-5 h-5 rotate-90 sm:rotate-0" />
```

- [ ] **Step 2: Stack two-branch tree vertically on mobile**

Change the two-branch container (line 183):
```heex
<div class="flex w-full max-w-2xl gap-4">
```
to:
```heex
<div class="flex flex-col md:flex-row w-full max-w-2xl gap-4">
```

Add overflow protection to the node cards — add `min-w-0` to the flex containers and ensure text truncates.

- [ ] **Step 3: Verify and commit**

```bash
git add lib/web/live/kinship_live.html.heex
git commit -m "feat: stack kinship selectors and branches on mobile"
```

---

## Task 14: Final Modal Sweep

Convert any remaining modals that don't use the bottom-sheet pattern on mobile.

**Files:**
- Check and fix any modals in pages modified in earlier tasks that were missed

- [ ] **Step 1: Grep for modals still using centered-only pattern**

```bash
grep -rn "flex items-center justify-center" lib/web/live/ --include="*.heex" --include="*.ex"
```

Any modal that has `items-center` without a `items-end lg:items-center` pattern needs conversion:
- Container: `items-center justify-center` → `items-end lg:items-center justify-center`
- Dialog: add `w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp` if not already present

- [ ] **Step 2: Fix any remaining modals**

Apply the bottom-sheet pattern to each one found.

- [ ] **Step 3: Verify and commit**

```bash
git add -A
git commit -m "fix: bottom-sheet modals on mobile for all remaining dialogs"
```

---

## Task 15: Run Precommit and Fix Issues

**Files:** Any files with warnings or formatting issues

- [ ] **Step 1: Run precommit**

```bash
mix precommit
```

- [ ] **Step 2: Fix any compilation warnings, formatting issues, or test failures**

Address each issue. Common ones:
- Unused imports (if bottom_sheet functions are no longer called in some pages)
- Formatting (run `mix format`)
- Test failures from changed DOM structure (update test selectors)

- [ ] **Step 3: Re-run precommit until clean**

```bash
mix precommit
```

Expected: All checks pass.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: fix precommit issues after mobile-first phase 2"
```
