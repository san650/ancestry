# Toolbar & Menu Reorganization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize toolbar actions, kebab menus, and mobile hamburger menus across all pages for consistent UX.

**Architecture:** Shared components (kebab menu, selection bar, nav drawer) are refactored first, then each page is updated to use them. Global changes (remove bottom nav, fix logo link) happen in the layout module.

**Tech Stack:** Phoenix LiveView, HEEx templates, Tailwind CSS, JS commands

**Spec:** `docs/plans/2026-04-26-toolbar-menu-reorganization-design.md`

---

## File Map

### Shared components (create or modify)

| File | Responsibility |
|------|---------------|
| `lib/web/components/layouts.ex` | Remove `bottom_nav/1`, fix logo href to `/org`, update toolbar slot rendering |
| `lib/web/components/nav_drawer.ex` | Remove icons from `nav_action/1`, add separator support, remove "Organizations" inner_block section, restructure slots |
| `lib/web/components/core_components.ex` | Add `kebab_menu/1` component, add `toolbar_button/1` component, add `selection_bar/1` component |

### Per-page templates (modify)

| File | Changes |
|------|---------|
| `lib/web/live/organization_live/index.html.heex` | Toolbar: text buttons, no icons. Selection bar: use shared component. Nav drawer: restructure. |
| `lib/web/live/family_live/index.html.heex` | Toolbar: text buttons + kebab. Selection bar: use shared component. Nav drawer: restructure. |
| `lib/web/live/family_live/show.html.heex` | Toolbar: text toggle + buttons + kebab. Nav drawer: restructure, remove icons. |
| `lib/web/live/family_live/show.ex` | Keep toggle_menu/close_menu, remove meatball-specific state if renamed. |
| `lib/web/live/gallery_live/show.html.heex` | Toolbar: text buttons. Selection bar: use shared component. Nav drawer: add hamburger + restructure. |
| `lib/web/live/person_live/show.html.heex` | Toolbar: "Edit" text button + kebab. Nav drawer: restructure. |
| `lib/web/live/people_live/index.html.heex` | Toolbar: "Select" text button. Filter chips: remove icons. Selection bar: use shared component. Nav drawer: add hamburger + restructure. |
| `lib/web/live/org_people_live/index.html.heex` | Same pattern as people_live/index. |
| `lib/web/live/vault_live/show.html.heex` | Toolbar: text buttons + kebab (delete only). Selection bar: use shared component. Nav drawer: add + restructure. |
| `lib/web/live/memory_live/show.html.heex` | Toolbar: "Edit" text button + kebab (delete only). Nav drawer: add. |
| `lib/web/live/memory_live/form.html.heex` | Nav drawer: add (navigation only). |
| `lib/web/live/birthday_live/index.ex` | Toolbar: breadcrumb + filter chip, remove back arrow. Nav drawer: add. |
| `lib/web/live/kinship_live.ex` | Nav drawer: add (navigation only). |
| `lib/web/live/person_live/new.html.heex` | Nav drawer: restructure (remove Organizations link). |
| `lib/web/live/family_live/new.html.heex` | Nav drawer: add (navigation only). |

---

## Task 1: Shared toolbar button component

Add a reusable `toolbar_button/1` to `core_components.ex` so every page can use consistent button styling.

**Files:**
- Modify: `lib/web/components/core_components.ex`

- [ ] **Step 1: Add toolbar_button component**

Add after the existing `button` component (around line 131):

```elixir
@doc """
A toolbar button with consistent styling.

## Variants

- `:primary` — coral background, white text (create/upload actions)
- `:secondary` — black border, surface background (select/edit/toggle)
- `:toggle_active` — indigo background, white text (active segmented toggle)
- `:filter` — border with optional gold highlight when active
- `:kebab` — square ⋮ button that triggers a dropdown

## Examples

    <.toolbar_button variant={:primary}>Upload</.toolbar_button>
    <.toolbar_button variant={:secondary} phx-click="toggle_select">Select</.toolbar_button>
    <.toolbar_button variant={:kebab} phx-click="toggle_menu" />
"""
attr :variant, :atom, default: :secondary, values: [:primary, :secondary, :toggle_active, :filter, :kebab]
attr :active, :boolean, default: false
attr :rest, :global, include: ~w(phx-click phx-value-id navigate href disabled)
slot :inner_block

def toolbar_button(assigns) do
  ~H"""
  <%= if @variant == :kebab do %>
    <button
      type="button"
      class="inline-flex items-center justify-center w-9 h-9 border-2 border-cm-black rounded-cm bg-cm-surface hover:bg-cm-surface/80 transition-colors"
      aria-label={gettext("More options")}
      {@rest}
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" class="size-4">
        <circle cx="8" cy="3" r="1.5" />
        <circle cx="8" cy="8" r="1.5" />
        <circle cx="8" cy="13" r="1.5" />
      </svg>
    </button>
  <% else %>
    <button
      type="button"
      class={[
        "px-3 py-1.5 rounded-cm font-cm-mono text-[10px] font-bold uppercase tracking-wider transition-colors",
        @variant == :primary && "bg-cm-coral text-cm-white border-2 border-cm-coral hover:opacity-90",
        @variant == :secondary && "bg-cm-surface text-cm-black border-2 border-cm-black hover:bg-cm-surface/80",
        @variant == :toggle_active && "bg-cm-indigo text-cm-white border-2 border-cm-indigo",
        @variant == :filter && !@active && "bg-cm-surface text-cm-black border border-cm-border hover:bg-cm-surface/80",
        @variant == :filter && @active && "bg-cm-golden text-cm-black border border-cm-golden font-bold"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
  <% end %>
  """
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no errors

- [ ] **Step 3: Commit**

```bash
git add lib/web/components/core_components.ex
git commit -m "Add shared toolbar_button component for consistent toolbar styling"
```

---

## Task 2: Shared kebab menu component

Add a reusable `kebab_menu/1` to `core_components.ex`.

**Files:**
- Modify: `lib/web/components/core_components.ex`

- [ ] **Step 1: Add kebab_menu component**

```elixir
@doc """
A kebab dropdown menu for toolbar overflow actions.

Renders a positioned dropdown with text-only menu items. Expects the parent
LiveView to manage `@show_menu` state with `toggle_menu` and `close_menu` events.

## Slots

- `item` — regular actions (above separator)
- `container_item` — edit/delete container actions (below separator, delete should use `danger` attr)

## Examples

    <.kebab_menu show={@show_menu}>
      <:item phx-click="print_tree">Print Tree</:item>
      <:item phx-click="manage_people">Manage People</:item>
      <:container_item phx-click="edit_family">Edit Family</:container_item>
      <:container_item danger phx-click="request_delete">Delete Family</:container_item>
    </.kebab_menu>
"""
attr :show, :boolean, required: true
attr :id, :string, default: "kebab-menu"
slot :item, doc: "Regular actions above the separator"
slot :container_item, doc: "Container edit/delete actions below separator"

def kebab_menu(assigns) do
  ~H"""
  <div :if={@show} id={@id} class="absolute right-0 top-full mt-1 w-56 bg-cm-white rounded-cm border-2 border-cm-black py-1 z-50 shadow-none" phx-click-away="close_menu">
    <div :for={item <- @item}>
      {render_slot(item)}
    </div>
    <div :if={@item != [] and @container_item != []} class="border-t border-cm-border my-1"></div>
    <div :for={item <- @container_item}>
      {render_slot(item)}
    </div>
  </div>
  """
end
```

**Usage pattern:** Each slot item renders its own button/link with styling. Use helper CSS classes for consistency. Call sites render the content inline:

```heex
<.kebab_menu show={@show_menu}>
  <:item>
    <button type="button" phx-click="some_event" class="kebab-item">Label</.button>
  </:item>
  <:container_item>
    <button type="button" phx-click="request_delete" class="kebab-item kebab-danger">Delete</.button>
  </:container_item>
</.kebab_menu>
```

**Alternative simpler approach:** Instead of slot-based rendering, define the kebab as a simple positioned container and have each call site render its own buttons inside an inner_block. This avoids slot complexity entirely. The implementer should choose the approach that works best — the key requirement is: positioned dropdown, text-only items, separator between regular and container actions, red text for danger items.
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no errors

- [ ] **Step 3: Commit**

```bash
git add lib/web/components/core_components.ex
git commit -m "Add shared kebab_menu component for toolbar overflow menus"
```

---

## Task 3: Shared selection bar component

Add a reusable `selection_bar/1` to `core_components.ex`.

**Files:**
- Modify: `lib/web/components/core_components.ex`

- [ ] **Step 1: Add selection_bar component**

```elixir
@doc """
A sticky selection toolbar that appears during multi-select mode.

Desktop: black background bar with counter and action buttons.
Mobile: bottom drawer (slide-up sheet) with counter and action buttons.

## Examples

    <.selection_bar count={MapSet.size(@selected_ids)} show={@selection_mode}>
      <:action phx-click="request_batch_delete" danger>Delete</:action>
    </.selection_bar>
"""
attr :count, :integer, required: true
attr :show, :boolean, required: true
attr :id, :string, default: "selection-bar"
slot :inner_block, required: true, doc: "Action buttons to render inside the bar"

def selection_bar(assigns) do
  ~H"""
  <%!-- Desktop: sticky bar at top of content area --%>
  <div
    :if={@show}
    id={@id}
    class="hidden lg:flex sticky top-0 z-30 bg-cm-black text-cm-white rounded-cm px-5 py-3 items-center justify-between mb-4"
    {test_id("selection-bar")}
  >
    <span class="font-cm-mono text-[10px] font-bold uppercase tracking-wider">
      {ngettext("1 selected", "%{count} selected", @count)}
    </span>
    <div class="flex items-center gap-2">
      {render_slot(@inner_block)}
    </div>
  </div>
  <%!-- Mobile: bottom drawer (slide-up sheet) --%>
  <div
    :if={@show}
    id={"#{@id}-mobile"}
    class="lg:hidden fixed bottom-0 left-0 right-0 z-30 bg-cm-white border-t-2 border-cm-black px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]"
  >
    <div class="flex items-center justify-between">
      <span class="font-cm-mono text-[10px] font-bold uppercase tracking-wider text-cm-black">
        {ngettext("1 selected", "%{count} selected", @count)}
      </span>
      <div class="flex items-center gap-2">
        {render_slot(@inner_block)}
      </div>
    </div>
  </div>
  """
end
```

**Usage pattern:** Call sites render action buttons directly inside the inner_block:

```heex
<.selection_bar count={MapSet.size(@selected_ids)} show={@selection_mode}>
  <button type="button" phx-click="request_batch_delete"
    class="px-3 py-2 font-cm-mono text-[10px] font-bold uppercase tracking-wider rounded-cm bg-cm-error text-white hover:opacity-90">
    Delete
  </button>
</.selection_bar>
```

This renders a sticky black bar on desktop and a fixed bottom sheet on mobile — matching the spec's requirement for dual-mode selection UI.
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no errors

- [ ] **Step 3: Commit**

```bash
git add lib/web/components/core_components.ex
git commit -m "Add shared selection_bar component for multi-select mode"
```

---

## Task 4: Global layout changes — remove bottom nav, fix logo

**Files:**
- Modify: `lib/web/components/layouts.ex`

- [ ] **Step 1: Remove `bottom_nav/1` function and its call**

In `lib/web/components/layouts.ex`:

1. Remove the `<.bottom_nav />` call from the `app/1` function (around line 128).
2. Delete the entire `bottom_nav/1` function definition (lines ~139-175).
3. Remove the `pb-16 lg:pb-0` padding that compensated for the bottom nav — find in the main content wrapper and change to just no extra bottom padding.

- [ ] **Step 2: Fix logo link to navigate to /org**

In `lib/web/components/layouts.ex`, find the logo link (line ~54):

Change:
```html
<a href="/" class="flex-1 flex w-fit items-center gap-3">
```

To:
```html
<a href="/org" class="flex-1 flex w-fit items-center gap-3">
```

- [ ] **Step 3: Verify it compiles and renders**

Run: `mix compile --warnings-as-errors`
Start the server: `iex -S mix phx.server`
Check: No bottom toolbar on any page. Logo navigates to `/org`.

- [ ] **Step 4: Commit**

```bash
git add lib/web/components/layouts.ex
git commit -m "Remove mobile bottom nav bar globally, fix logo to navigate to /org"
```

---

## Task 5: Update nav drawer — remove icons, restructure

The nav drawer needs to change from icon+text actions to text-only actions. The slot structure stays but the `nav_action` component drops its icon.

**Files:**
- Modify: `lib/web/components/nav_drawer.ex`

- [ ] **Step 1: Update `nav_action/1` to remove icon**

Change `nav_action/1` to render text-only, no icon. Make the `icon` attribute optional and ignored (so existing call sites don't break during the transition — we remove icons from call sites in per-page tasks). Add `danger` styling. Render as `<.link>` when `navigate` is present (buttons don't support `navigate`), otherwise render as `<button>`:

```elixir
attr :label, :string, required: true
attr :danger, :boolean, default: false
attr :icon, :string, default: nil, doc: "Deprecated — ignored, kept for transition compatibility"
attr :navigate, :string, default: nil
attr :rest, :global, include: ~w(phx-click href)

def nav_action(assigns) do
  ~H"""
  <%= if @navigate do %>
    <.link
      navigate={@navigate}
      class={[
        "block w-full text-left px-4 py-3 font-cm-mono text-[11px] font-bold uppercase tracking-wider transition-colors min-h-[44px]",
        if(@danger, do: "text-cm-error hover:bg-cm-error/10", else: "text-cm-black hover:bg-cm-surface")
      ]}
      {@rest}
    >
      {@label}
    </.link>
  <% else %>
    <button
      type="button"
      class={[
        "block w-full text-left px-4 py-3 font-cm-mono text-[11px] font-bold uppercase tracking-wider transition-colors min-h-[44px]",
        if(@danger, do: "text-cm-error hover:bg-cm-error/10", else: "text-cm-black hover:bg-cm-surface")
      ]}
      {@rest}
    >
      {@label}
    </button>
  <% end %>
  """
end
```

**Note:** Keeping `icon` as an optional ignored attr means Task 5 will compile even before per-page tasks remove the `icon=` usages. This avoids a broken compilation state between tasks.

- [ ] **Step 2: Add `nav_separator/1` component**

```elixir
def nav_separator(assigns) do
  ~H"""
  <div class="border-t border-cm-border my-1 mx-4"></div>
  """
end
```

- [ ] **Step 3: Remove "Organizations" inner_block section from the nav drawer**

In the `nav_drawer/1` function, remove the inner_block rendering section (the part that renders organization links). The website icon now handles root navigation.

- [ ] **Step 4: Update account section at bottom to use text-only nav_actions**

The Settings/Accounts/Log Out links at the bottom of the nav drawer should use `nav_action` with no icons.

- [ ] **Step 5: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no errors (the deprecated `icon` attr ensures backward compatibility during transition).

- [ ] **Step 6: Commit**

```bash
git add lib/web/components/nav_drawer.ex
git commit -m "Update nav_drawer: text-only actions, add separator, remove Organizations section"
```

---

## Task 6: Organization Index page

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex`

- [ ] **Step 1: Update desktop toolbar**

Replace the current toolbar content with:
- "Select" — `<.toolbar_button variant={:secondary} phx-click="toggle_select_mode">Select</.toolbar_button>`
- "New Organization" — `<.toolbar_button variant={:primary} phx-click="new_organization">New Organization</.toolbar_button>`

Remove all icon references from toolbar buttons.

**Existing event names:** `"toggle_select_mode"`, `"new_organization"`, `"rename_selected"`, `"request_batch_delete"`.

- [ ] **Step 2: Update selection bar**

Replace the inline selection bar with the shared `<.selection_bar>` component:
```heex
<.selection_bar count={MapSet.size(@selected_ids)} show={@selection_mode}>
  <:action phx-click="rename_selected" disabled={MapSet.size(@selected_ids) != 1}>Rename</:action>
  <:action phx-click="request_batch_delete" danger>Delete</:action>
</.selection_bar>
```

- [ ] **Step 3: Update nav drawer**

Replace nav drawer contents with text-only actions:
```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={gettext("Select")} phx-click={toggle_nav_drawer() |> JS.push("toggle_select_mode")} />
    <.nav_action label={gettext("New Organization")} phx-click={toggle_nav_drawer() |> JS.push("new_organization")} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 4: Verify it compiles and test in browser**

Run: `mix compile --warnings-as-errors`
Test in browser at `/org`: toolbar shows text buttons, no icons. Hamburger menu shows text-only actions. Selection mode works. No bottom toolbar.

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/organization_live/index.html.heex
git commit -m "Organization Index: text-only toolbar buttons, shared selection bar, restructured nav drawer"
```

---

## Task 7: Family Index page

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex`
- Modify: `lib/web/live/family_live/index.ex` (add toggle_menu/close_menu handlers if not present)

- [ ] **Step 1: Update desktop toolbar**

Replace with:
- "Select" text button (secondary)
- "New Family" text button (primary/coral)
- Kebab `⋮` button (opens menu with "People" link)

Add `@show_menu` state to the LiveView mount if not present.

- [ ] **Step 2: Add kebab menu**

```heex
<div class="relative">
  <.toolbar_button variant={:kebab} phx-click="toggle_menu" />
  <.kebab_menu show={@show_menu}>
    <:item navigate={~p"/org/#{@current_scope.organization.id}/people"}>People</:item>
  </.kebab_menu>
</div>
```

- [ ] **Step 3: Update selection bar to shared component**

Replace inline selection bar with `<.selection_bar>`.

- [ ] **Step 4: Update nav drawer**

Note: "New Family" is a navigation link (to `/families/new`), not a modal event.

```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={gettext("Select")} phx-click={toggle_nav_drawer() |> JS.push("toggle_select_mode")} />
    <.nav_action label={gettext("People")} navigate={~p"/org/#{@current_scope.organization.id}/people"} />
    <.nav_action label={gettext("New Family")} navigate={~p"/org/#{@current_scope.organization.id}/families/new"} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 5: Add show_menu state and handlers to LiveView**

In `lib/web/live/family_live/index.ex`, add to mount:
```elixir
|> assign(:show_menu, false)
```

Add handlers:
```elixir
def handle_event("toggle_menu", _, socket) do
  {:noreply, assign(socket, :show_menu, !socket.assigns.show_menu)}
end

def handle_event("close_menu", _, socket) do
  {:noreply, assign(socket, :show_menu, false)}
end
```

- [ ] **Step 6: Verify and test**

Run: `mix compile --warnings-as-errors`
Test in browser: toolbar, kebab, selection, nav drawer all work.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/family_live/index.html.heex lib/web/live/family_live/index.ex
git commit -m "Family Index: text-only toolbar, kebab menu with People, shared selection bar"
```

---

## Task 8: Family Show page

This is the most complex page. Toolbar gets segmented text toggle, text buttons, and a kebab menu with many items.

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`
- Modify: `lib/web/live/family_live/show.ex` (if needed for menu state)

- [ ] **Step 1: Replace desktop toolbar**

Replace icon buttons with:
1. Graph/Tree segmented text toggle. **Note:** `@view_mode` is a string (`"graph"` or `"tree"`), not an atom. The existing `switch_view` handler expects `%{"view" => value}`, not `%{"mode" => value}`:
```heex
<div class="flex border-2 border-cm-black rounded-cm overflow-hidden">
  <button
    type="button"
    phx-click="switch_view"
    phx-value-view="graph"
    class={[
      "px-3 py-1.5 font-cm-mono text-[10px] font-bold uppercase tracking-wider transition-colors",
      if(@view_mode == "graph", do: "bg-cm-indigo text-cm-white", else: "bg-cm-surface text-cm-black hover:bg-cm-surface/80")
    ]}
  >
    {gettext("Graph")}
  </button>
  <button
    type="button"
    phx-click="switch_view"
    phx-value-view="tree"
    class={[
      "px-3 py-1.5 font-cm-mono text-[10px] font-bold uppercase tracking-wider transition-colors border-l-2 border-cm-black",
      if(@view_mode == "tree", do: "bg-cm-indigo text-cm-white", else: "bg-cm-surface text-cm-black hover:bg-cm-surface/80")
    ]}
  >
    {gettext("Tree")}
  </button>
</div>
```

2. "Kinship" secondary text button (navigate to kinship page)
3. "Birthdays" secondary text button (navigate to birthdays page)
4. Kebab `⋮` button

- [ ] **Step 2: Replace meatball menu with kebab_menu component**

**Existing event names:** `"edit"`, `"request_delete"`, `"open_import"`, `"open_create_subfamily"`, `"toggle_menu"`, `"close_menu"`. Print tree is a link to `@print_url` (not an event).

```heex
<div class="relative">
  <.toolbar_button variant={:kebab} phx-click="toggle_menu" />
  <.kebab_menu show={@show_menu}>
    <:item :if={@graph} navigate={@print_url}>Print Tree</:item>
    <:item navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/people"}>Manage People</:item>
    <:item phx-click="open_import">Import from CSV</:item>
    <:item :if={@people != []} phx-click="open_create_subfamily">Create Subfamily</:item>
    <:container_item phx-click="edit">Edit Family</:container_item>
    <:container_item danger phx-click="request_delete">Delete Family</:container_item>
  </.kebab_menu>
</div>
```

- [ ] **Step 3: Remove all icon-only action buttons from toolbar**

Remove the edit (pencil), delete (trash), and kinship (arrows) icon buttons. They are now in the kebab or as text buttons.

- [ ] **Step 4: Update nav drawer**

Replace icon+text nav_actions with text-only. **Important:** Keep the existing `<:page_panel>` slot content (SidePanelComponent with people search, galleries, vaults) — only change `<:page_actions>` and remove the inner_block Organizations link.

```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action
      label={if(@view_mode == "graph", do: gettext("Tree View"), else: gettext("Graph View"))}
      phx-click={toggle_nav_drawer() |> JS.push("switch_view", value: %{view: if(@view_mode == "graph", do: "tree", else: "graph")})}
    />
    <.nav_action label={gettext("Tree Settings")} phx-click={toggle_nav_drawer() |> JS.push("open_mobile_tree_sheet")} />
    <.nav_action label={gettext("Kinship Calculator")} navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/kinship"} />
    <.nav_action label={gettext("Birthdays")} navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/birthdays"} />
    <.nav_action label={gettext("Manage People")} navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/people"} />
    <.nav_action label={gettext("Import from CSV")} phx-click={toggle_nav_drawer() |> JS.push("open_import")} />
    <.nav_action :if={@people != []} label={gettext("Create Subfamily")} phx-click={toggle_nav_drawer() |> JS.push("open_create_subfamily")} />
    <.nav_action label={gettext("Edit Family")} phx-click={toggle_nav_drawer() |> JS.push("edit")} />
    <.nav_action :if={@graph} label={gettext("Print Tree")} navigate={@print_url} />
    <.nav_action label={gettext("Delete Family")} danger phx-click={toggle_nav_drawer() |> JS.push("request_delete")} />
  </:page_actions>
  <:page_panel>
    <%!-- Keep existing SidePanelComponent content unchanged --%>
  </:page_panel>
</.nav_drawer>
```

- [ ] **Step 5: Verify and test**

Run: `mix compile --warnings-as-errors`
Test in browser at `/org/:id/families/:fid`: segmented toggle works, kebab opens with correct items, nav drawer has all actions text-only.

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/family_live/show.html.heex lib/web/live/family_live/show.ex
git commit -m "Family Show: text segmented toggle, text toolbar buttons, kebab menu, restructured nav drawer"
```

---

## Task 9: Gallery Show page

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex`
- Modify: `lib/web/live/gallery_live/show.ex` (if needed)

- [ ] **Step 1: Update desktop toolbar**

Replace icon buttons with text buttons:
- "Select" (secondary) — `phx-click="toggle_select_mode"`
- "Masonry" / "Uniform" toggle (secondary, text changes based on `@grid_layout`) — `phx-click="toggle_layout"`
- "Upload" (primary/coral) — **Note:** Upload is form-based via `allow_upload` with `auto_upload: true`. The existing upload button triggers a file input. Keep the same upload mechanism, just restyle to a text button.

- [ ] **Step 2: Update selection bar to shared component**

Replace inline selection bar with `<.selection_bar>`.

- [ ] **Step 3: Add nav drawer**

Add hamburger button to toolbar (mobile only). Add nav drawer:
```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={gettext("Select")} phx-click={toggle_nav_drawer() |> JS.push("toggle_select_mode")} />
    <.nav_action label={gettext("Upload Photos")} phx-click={toggle_nav_drawer() |> JS.push("upload_photos")} />
    <.nav_action label={if(@grid_layout == :masonry, do: gettext("Uniform"), else: gettext("Masonry"))} phx-click={toggle_nav_drawer() |> JS.push("toggle_layout")} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 4: Verify and test**

Run: `mix compile --warnings-as-errors`
Test in browser: text buttons, selection bar, hamburger menu all work.

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/gallery_live/show.html.heex lib/web/live/gallery_live/show.ex
git commit -m "Gallery Show: text-only toolbar, shared selection bar, add nav drawer"
```

---

## Task 10: Person Show page

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`
- Modify: `lib/web/live/person_live/show.ex` (add show_menu state + handlers)

- [ ] **Step 1: Update desktop toolbar**

Replace icon buttons with:
- "Edit" (secondary text button)
- Kebab `⋮` button

- [ ] **Step 2: Add kebab menu**

**Existing event names:** `"edit"`, `"request_remove"`, `"convert_to_acquaintance"`, `"request_delete"`. Conditionals: `@from_family` (truthy when navigated from family), `not Ancestry.People.Person.acquaintance?(@person)` for convert.

```heex
<div class="relative">
  <.toolbar_button variant={:kebab} phx-click="toggle_menu" />
  <.kebab_menu show={@show_menu}>
    <:item :if={@from_family} phx-click="request_remove">Remove from Family</:item>
    <:item :if={not Ancestry.People.Person.acquaintance?(@person)} phx-click="convert_to_acquaintance">Convert to Non-family</:item>
    <:container_item danger phx-click="request_delete">Delete Person</:container_item>
  </.kebab_menu>
</div>
```

- [ ] **Step 3: Remove desktop-only icon buttons**

Remove the hidden `lg:flex` div containing edit/remove/delete/convert icon buttons.

- [ ] **Step 4: Update nav drawer**

```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={gettext("Edit")} phx-click={toggle_nav_drawer() |> JS.push("edit")} />
    <.nav_action :if={@from_family} label={gettext("Remove from Family")} phx-click={toggle_nav_drawer() |> JS.push("request_remove")} />
    <.nav_action :if={not Ancestry.People.Person.acquaintance?(@person)} label={gettext("Convert to Non-family")} phx-click={toggle_nav_drawer() |> JS.push("convert_to_acquaintance")} />
    <.nav_action label={gettext("Delete Person")} danger phx-click={toggle_nav_drawer() |> JS.push("request_delete")} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 5: Add show_menu state and handlers**

In `lib/web/live/person_live/show.ex`, add `show_menu: false` to mount assigns and add toggle_menu/close_menu handlers.

- [ ] **Step 6: Verify and test**

Run: `mix compile --warnings-as-errors`
Test in browser: "Edit" text button, kebab with conditional items, nav drawer works.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/person_live/show.html.heex lib/web/live/person_live/show.ex
git commit -m "Person Show: Edit text button, kebab menu with conditional actions, restructured nav drawer"
```

---

## Task 11: People List — Family

**Files:**
- Modify: `lib/web/live/people_live/index.html.heex`
- Modify: `lib/web/live/people_live/index.ex` (rename editing to selection_mode if needed)

- [ ] **Step 1: Update desktop toolbar**

Replace "Edit"/"Done" toggle with "Select" text button (secondary). Remove icon from the button.

- [ ] **Step 2: Remove icons from filter chips**

Change "Unlinked" and "Non-family" filter chips to text-only (remove `<.icon>` elements). Keep gold highlight behavior.

- [ ] **Step 3: Update selection bar to shared component**

**Existing event names:** `"toggle_edit"`, `"request_remove"`, `"toggle_select"`, `"select_all"`, `"deselect_all"`.

Replace inline selection controls with `<.selection_bar>`:
```heex
<.selection_bar count={MapSet.size(@selected)} show={@editing}>
  <:action phx-click="request_remove" danger>Remove from Family</:action>
</.selection_bar>
```

- [ ] **Step 4: Add nav drawer**

Add hamburger button to toolbar. Add nav drawer with "Select" action:
```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={if(@editing, do: gettext("Done"), else: gettext("Select"))} phx-click={toggle_nav_drawer() |> JS.push("toggle_edit")} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 5: Verify and test**

Run: `mix compile --warnings-as-errors`
Test: text buttons, filter chips without icons, selection bar, nav drawer.

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/people_live/index.html.heex lib/web/live/people_live/index.ex
git commit -m "People List (Family): text-only toolbar and filters, shared selection bar, add nav drawer"
```

---

## Task 12: People List — Org

Same pattern as Task 11 but for org-wide people list.

**Files:**
- Modify: `lib/web/live/org_people_live/index.html.heex`
- Modify: `lib/web/live/org_people_live/index.ex`

- [ ] **Step 1: Update desktop toolbar**

Replace "Edit"/"Done" with "Select" text button.

- [ ] **Step 2: Remove icons from filter chips**

Remove icons from "No family" and "Non-family" chips.

- [ ] **Step 3: Update selection bar to shared component**

**Existing event names:** `"toggle_edit"`, `"request_delete"`, `"toggle_select"`, `"select_all"`, `"deselect_all"`.

```heex
<.selection_bar count={MapSet.size(@selected)} show={@editing}>
  <:action phx-click="request_delete" danger>Delete</:action>
</.selection_bar>
```

- [ ] **Step 4: Add nav drawer**

Same pattern as People List Family (using `"toggle_edit"` event).

- [ ] **Step 5: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/org_people_live/index.html.heex lib/web/live/org_people_live/index.ex
git commit -m "Org People List: text-only toolbar and filters, shared selection bar, add nav drawer"
```

---

## Task 13: Vault Show page

**Files:**
- Modify: `lib/web/live/vault_live/show.html.heex`
- Modify: `lib/web/live/vault_live/show.ex` (add show_menu state)

- [ ] **Step 1: Update desktop toolbar**

Replace icon buttons with:
- "Select" (secondary text button)
- "Add Memory" (primary/coral text button)
- Kebab `⋮` button

- [ ] **Step 2: Add kebab menu**

```heex
<div class="relative">
  <.toolbar_button variant={:kebab} phx-click="toggle_menu" />
  <.kebab_menu show={@show_menu}>
    <:container_item danger phx-click="request_delete_vault">Delete Vault</:container_item>
  </.kebab_menu>
</div>
```

- [ ] **Step 3: Update selection bar to shared component**

Replace inline selection bar with `<.selection_bar>`.

- [ ] **Step 4: Add nav drawer**

```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={gettext("Select")} phx-click={toggle_nav_drawer() |> JS.push("toggle_select_mode")} />
    <.nav_action label={gettext("Add Memory")} navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}/memories/new"} />
    <.nav_action label={gettext("Delete Vault")} danger phx-click={toggle_nav_drawer() |> JS.push("request_delete_vault")} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 5: Add show_menu state and handlers**

- [ ] **Step 6: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/vault_live/show.html.heex lib/web/live/vault_live/show.ex
git commit -m "Vault Show: text-only toolbar, kebab with delete, shared selection bar, add nav drawer"
```

---

## Task 14: Memory Show page

**Files:**
- Modify: `lib/web/live/memory_live/show.html.heex`
- Modify: `lib/web/live/memory_live/show.ex` (add show_menu state)

- [ ] **Step 1: Update desktop toolbar**

Replace icon+text "Edit" button with text-only secondary button. Add kebab.

- [ ] **Step 2: Add kebab menu**

```heex
<div class="relative">
  <.toolbar_button variant={:kebab} phx-click="toggle_menu" />
  <.kebab_menu show={@show_menu}>
    <:container_item danger phx-click="request_delete">Delete Memory</:container_item>
  </.kebab_menu>
</div>
```

- [ ] **Step 3: Add nav drawer**

```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action label={gettext("Edit")} navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/vaults/#{@vault.id}/memories/#{@memory.id}/edit"} />
    <.nav_action label={gettext("Delete Memory")} danger phx-click={toggle_nav_drawer() |> JS.push("request_delete")} />
  </:page_actions>
</.nav_drawer>
```

- [ ] **Step 4: Add show_menu state, toggle_menu/close_menu handlers, and request_delete handler**

**Note:** Memory Show currently has NO handle_event functions (only mount and handle_params). Add:
- `show_menu: false` assign in mount
- `toggle_menu` / `close_menu` handlers
- `request_delete` handler (to set `confirm_delete: true` — check if this already exists as an assign; the delete modal already exists in the form page, so the show page may need a delete confirmation flow added)

- [ ] **Step 5: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/memory_live/show.html.heex lib/web/live/memory_live/show.ex
git commit -m "Memory Show: Edit text button, kebab with delete, add nav drawer"
```

---

## Task 15: Memory Form page

**Files:**
- Modify: `lib/web/live/memory_live/form.html.heex`

- [ ] **Step 1: Add hamburger button and nav drawer**

Add hamburger button to toolbar (mobile only). Add minimal nav drawer (navigation only, no page actions):

```heex
<.nav_drawer current_scope={@current_scope} />
```

- [ ] **Step 2: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/memory_live/form.html.heex
git commit -m "Memory Form: add nav drawer for mobile navigation"
```

---

## Task 16: Birthday Index page

**Files:**
- Modify: `lib/web/live/birthday_live/index.ex`

- [ ] **Step 1: Add toolbar with breadcrumb and filter chip**

Replace the current inline header (back arrow + title + toggle) with a proper `<:toolbar>` slot containing:
- Breadcrumb navigation
- "Show all" filter chip using `<.toolbar_button variant={:filter} active={@show_all}>`

Remove the back arrow link.

- [ ] **Step 2: Add hamburger button and nav drawer**

Add hamburger button (mobile only) and minimal nav drawer.

- [ ] **Step 3: Verify and test**

Run: `mix compile --warnings-as-errors`
Test: breadcrumb renders, filter chip toggles, no back arrow.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/birthday_live/index.ex
git commit -m "Birthday Index: breadcrumb toolbar, filter chip, remove back arrow, add nav drawer"
```

---

## Task 17: Kinship Calculator page

**Files:**
- Modify: `lib/web/live/kinship_live.ex`

- [ ] **Step 1: Add hamburger button and nav drawer**

Add hamburger button to the page (mobile only) and a minimal nav drawer. The page may need a toolbar slot added if it doesn't have one.

- [ ] **Step 2: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/kinship_live.ex
git commit -m "Kinship Calculator: add nav drawer for mobile navigation"
```

---

## Task 18: Person New page

**Files:**
- Modify: `lib/web/live/person_live/new.html.heex`

- [ ] **Step 1: Update nav drawer**

Remove the "Organizations" link from the nav drawer. Keep it minimal with just the standard navigation section:

```heex
<.nav_drawer current_scope={@current_scope} />
```

- [ ] **Step 2: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/person_live/new.html.heex
git commit -m "Person New: remove Organizations link from nav drawer"
```

---

## Task 19: Family New page

**Files:**
- Modify: `lib/web/live/family_live/new.html.heex`

- [ ] **Step 1: Add hamburger button and nav drawer**

Check if this page has a hamburger and nav drawer. If not, add them. The nav drawer should be minimal (navigation only).

- [ ] **Step 2: Verify and test**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/family_live/new.html.heex
git commit -m "Family New: add nav drawer for mobile navigation"
```

---

## Task 20: Final verification

- [ ] **Step 1: Run full test suite**

Run: `mix precommit`
Expected: all tests pass, no warnings.

- [ ] **Step 2: Manual browser walkthrough**

Visit every page and verify:
1. Desktop toolbar has text buttons only (no icons)
2. Kebab menus open/close correctly with proper item ordering
3. Selection mode shows sticky secondary toolbar on desktop
4. Mobile hamburger menus have correct text-only options in correct order
5. No bottom mobile toolbar on any page
6. Logo navigates to `/org`
7. Filter chips on people/birthday pages have no icons

- [ ] **Step 3: Fix any issues found**

- [ ] **Step 4: Final commit**

```bash
git commit -m "Toolbar & menu reorganization: final fixes"
```
