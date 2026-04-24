# Print Family Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dedicated print page for the family tree — opens in a new tab, shows family name + text-only person cards with SVG connectors, auto-triggers `window.print()`.

**Architecture:** New LiveView with minimal layout, separate print graph component, reuses `PersonGraph` and `GraphConnector` hook.

**Tech Stack:** Phoenix LiveView, Tailwind CSS v4, JS hooks

**Spec:** `docs/plans/2026-04-24-print-family-tree-design.md`

---

### Task 1: Add `print/1` layout function

**Files:**
- Modify: `lib/web/components/layouts.ex`

- [ ] **Step 1: Add the `print` layout function**

Add after the `app/1` function (before `flash_group`). This is a minimal layout with no header, toolbar, or nav — just the page content on a white background:

```elixir
@doc """
Minimal layout for print pages. No header, toolbar, or navigation.
"""
attr :flash, :map, required: true, doc: "the map of flash messages"
slot :inner_block, required: true

def print(assigns) do
  ~H"""
  <div class="bg-white min-h-screen p-6">
    {render_slot(@inner_block)}
  </div>
  """
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/components/layouts.ex
git commit -m "Add print layout function to Layouts"
```

---

### Task 2: Create `PrintGraphComponent`

**Files:**
- Create: `lib/web/live/family_live/print_graph_component.ex`

- [ ] **Step 1: Create the print graph component**

This component renders the same CSS grid structure as `GraphComponent` but with simplified person cards — just a bordered box with the person's name.

```elixir
defmodule Web.FamilyLive.PrintGraphComponent do
  use Web, :html

  alias Ancestry.People.Person
  alias Ancestry.People.PersonGraph

  # --- Print Graph Canvas ---

  attr :graph, PersonGraph, required: true

  def print_graph_canvas(assigns) do
    ~H"""
    <div
      id="graph-canvas"
      phx-hook="GraphConnector"
      data-edges={Jason.encode!(@graph.edges)}
      class="relative overflow-visible"
    >
      <div
        data-graph-grid
        style={"display:grid; grid-template-columns:repeat(#{@graph.grid_cols}, 120px); grid-template-rows:repeat(#{@graph.grid_rows}, auto); gap:48px 12px;"}
        class="w-fit mx-auto"
      >
        <%= for node <- @graph.nodes do %>
          <.print_cell node={node} />
        <% end %>
      </div>
    </div>
    """
  end

  # --- Print Cell ---

  defp print_cell(%{node: %{type: :separator}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1}"}
      aria-hidden="true"
    />
    """
  end

  defp print_cell(%{node: %{type: :person}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      data-node-id={@node.id}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1}"}
      class="flex items-center justify-center"
    >
      <.print_person_card person={@node.person} />
    </div>
    """
  end

  # --- Print Person Card ---

  defp print_person_card(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-center text-center w-[120px] px-1 py-2",
      "bg-white border border-gray-300 rounded-sm",
      gender_border_class(@person.gender)
    ]}>
      <p class="text-xs font-medium text-black leading-tight line-clamp-2">
        {Person.display_name(@person)}
      </p>
    </div>
    """
  end

  defp gender_border_class("male"), do: "border-t-2 border-t-blue-400"
  defp gender_border_class("female"), do: "border-t-2 border-t-pink-400"
  defp gender_border_class(_), do: "border-t-2 border-t-gray-400"
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/family_live/print_graph_component.ex
git commit -m "Add PrintGraphComponent with text-only person cards"
```

---

### Task 3: Create `AutoPrint` JS hook

**Files:**
- Create: `assets/js/auto_print.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create the AutoPrint hook**

```javascript
// assets/js/auto_print.js
//
// AutoPrint — triggers window.print() after the page has rendered.
// Waits for the GraphConnector hook to finish drawing SVG connectors.

const AutoPrint = {
  mounted() {
    // Give the GraphConnector hook time to draw SVG connectors,
    // then trigger the print dialog.
    setTimeout(() => window.print(), 500)
  },
}

export { AutoPrint }
```

- [ ] **Step 2: Register the hook in app.js**

In `assets/js/app.js`, find the existing hook imports and add:

```javascript
import { AutoPrint } from "./auto_print"
```

Then add `AutoPrint` to the hooks object in the LiveSocket constructor:

```javascript
hooks: { GraphConnector, AutoPrint, ... }
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 4: Commit**

```bash
git add assets/js/auto_print.js assets/js/app.js
git commit -m "Add AutoPrint JS hook for print page"
```

---

### Task 4: Create Print LiveView and template

**Files:**
- Create: `lib/web/live/family_live/print.ex`
- Create: `lib/web/live/family_live/print.html.heex`

- [ ] **Step 1: Create the LiveView**

The mount loads the family and builds the graph. It reuses the same data loading pattern as `FamilyLive.Show` but only loads what's needed for the graph.

```elixir
defmodule Web.FamilyLive.Print do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.PersonGraph
  alias Ancestry.Relationships

  import Web.FamilyLive.PrintGraphComponent

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    people = People.list_people_for_family(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    family_graph = FamilyGraph.from(people, relationships, family.id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:people, people)
     |> assign(:family_graph, family_graph)
     |> assign(:page_title, family.name)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    people = socket.assigns.people

    focus_person =
      case params do
        %{"person" => id} ->
          person_id = String.to_integer(id)
          Enum.find(people, &(&1.id == person_id))

        _ ->
          case People.get_default_person(socket.assigns.family.id) do
            nil -> List.first(people)
            default -> Enum.find(people, &(&1.id == default.id))
          end
      end

    tree_ancestors = parse_depth(params, "ancestors", 2)
    tree_descendants = parse_depth(params, "descendants", 2)
    tree_other = parse_depth(params, "other", 1)

    {tree_ancestors, tree_descendants, tree_other} =
      if params["display"] == "complete" do
        {20, 20, 20}
      else
        {tree_ancestors, tree_descendants, min(tree_other, tree_ancestors)}
      end

    graph =
      if focus_person do
        PersonGraph.build(focus_person, socket.assigns.family_graph,
          ancestors: tree_ancestors,
          descendants: tree_descendants,
          other: tree_other
        )
      end

    {:noreply, assign(socket, :graph, graph)}
  end

  defp parse_depth(params, key, default) do
    case Integer.parse(params[key] || "") do
      {n, _} when n >= 1 and n <= 20 -> n
      _ -> default
    end
  end
end
```

- [ ] **Step 2: Create the template**

```heex
<Layouts.print flash={@flash}>
  <h1 class="text-2xl font-bold text-black text-center mb-6">
    {@family.name}
  </h1>

  <%= if @graph do %>
    <div id="print-page" phx-hook="AutoPrint">
      <.print_graph_canvas graph={@graph} />
    </div>
  <% else %>
    <p class="text-center text-gray-500">
      {gettext("No tree to display")}
    </p>
  <% end %>
</Layouts.print>
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/print.ex lib/web/live/family_live/print.html.heex
git commit -m "Add Print LiveView and template"
```

---

### Task 5: Add route

**Files:**
- Modify: `lib/web/router.ex`

- [ ] **Step 1: Add the print route**

In the `:organization` live_session block, after the `FamilyLive.Show` route (line 71), add:

```elixir
live "/families/:family_id/print", FamilyLive.Print, :print
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/router.ex
git commit -m "Add print route for family tree"
```

---

### Task 6: Add "Print tree" button to family show page

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

- [ ] **Step 1: Build the print URL helper**

In `lib/web/live/family_live/show.ex`, add a private helper function that builds the print URL from the current tree state:

```elixir
defp print_url(socket) do
  org_id = socket.assigns.current_scope.organization.id
  family_id = socket.assigns.family.id
  params = %{}

  params =
    if socket.assigns.focus_person,
      do: Map.put(params, :person, socket.assigns.focus_person.id),
      else: params

  params =
    if socket.assigns.tree_display == "complete" do
      Map.put(params, :display, "complete")
    else
      params
      |> Map.put(:ancestors, socket.assigns.tree_ancestors)
      |> Map.put(:descendants, socket.assigns.tree_descendants)
      |> Map.put(:other, socket.assigns.tree_other)
    end

  ~p"/org/#{org_id}/families/#{family_id}/print?#{params}"
end
```

- [ ] **Step 2: Add to meatball menu (desktop)**

In `show.html.heex`, add a "Print tree" link inside the meatball dropdown (after the "Import from CSV" button), as the last item:

```heex
<.link
  :if={@graph}
  href={print_url(@socket)}
  target="_blank"
  class="flex items-center gap-3 px-4 py-2.5 text-sm text-ds-on-surface hover:bg-ds-surface-low transition-colors"
  {test_id("family-print-btn")}
>
  <.icon name="hero-printer" class="size-4 text-ds-on-surface-variant" />
  <span>{gettext("Print tree")}</span>
</.link>
```

- [ ] **Step 3: Add to nav drawer (mobile)**

In the `<:page_actions>` slot of the nav drawer, add after the "Kinship calculator" action:

```heex
<.nav_action
  :if={@graph}
  icon="hero-printer"
  label={gettext("Print tree")}
  phx-click={JS.navigate(print_url(@socket), replace: false)}
/>
```

Note: `nav_action` uses `phx-click`, so we need to use `JS.navigate` to open in a new tab. Actually, since `nav_action` is a button, we can't use `target="_blank"`. Instead, use a direct `<.link>` styled like a nav action:

```heex
<.link
  :if={@graph}
  href={print_url(@socket)}
  target="_blank"
  class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] transition-colors hover:bg-ds-surface-high text-ds-on-surface"
>
  <.icon name="hero-printer" class="size-5 shrink-0" />
  <span class="font-ds-body text-sm">{gettext("Print tree")}</span>
</.link>
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "Add Print tree button to family show page"
```

---

### Task 7: Add CLAUDE.md for family_live

**Files:**
- Create: `lib/web/live/family_live/CLAUDE.md`

- [ ] **Step 1: Create the CLAUDE.md**

```markdown
# Family Live

## Print page

The family tree has a dedicated print page (`print.ex` + `print.html.heex`) that opens in a new tab.

- `PrintGraphComponent` renders the tree with simplified text-only person cards — keep this component separate from `GraphComponent` so each can evolve independently
- Both components consume the same `PersonGraph` struct — changes to graph computation apply to both views automatically
- Both use the `GraphConnector` JS hook for SVG connectors
```

- [ ] **Step 2: Commit**

```bash
git add lib/web/live/family_live/CLAUDE.md
git commit -m "Add CLAUDE.md documenting print page relationship"
```

---

### Task 8: Verification

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: all checks pass

- [ ] **Step 2: Manual test**

1. Start dev server: `iex -S mix phx.server`
2. Navigate to a family with a tree
3. Open the meatball menu → click "Print tree"
4. Verify: new tab opens with family name + text-only person cards + SVG connectors
5. Verify: print dialog auto-opens
6. Verify: the tree fits the page (no clipping)
7. On mobile viewport: verify "Print tree" appears in nav drawer
