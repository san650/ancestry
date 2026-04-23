# Tree View Depth Controls — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable drawer panel (desktop) and bottom sheet (mobile) that lets users control tree view depth (ancestors, descendants, laterals), and implement the "other" (lateral) traversal in `PersonGraph`.

**Architecture:** URL params (`?ancestors=N&descendants=N&other=N&display=partial|complete`) are the source of truth, read in `handle_params` and stored in socket assigns. Slider changes patch the URL, triggering a graph rebuild with the cached `FamilyGraph`. The desktop drawer open/close is JS-only. The "other" traversal is added as a new phase in `PersonGraph.build/3` after ancestors and descendants.

**Tech Stack:** Phoenix LiveView, Tailwind CSS, vanilla JS hook, Elixir

**Spec:** `docs/plans/2026-04-23-tree-view-depth-controls-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/ancestry/people/person_graph.ex` | Modify | Change default `other: 1`, implement lateral traversal |
| `lib/web/live/family_live/show.ex` | Modify | Read depth params in `handle_params`, add slider events, update `focus_person`/`refresh_graph` to carry depth params |
| `lib/web/live/family_live/show.html.heex` | Modify | Add desktop drawer, mobile header button + bottom sheet |
| `assets/js/tree_drawer.js` | Create | JS hook for drawer open/close toggle |
| `assets/js/app.js` | Modify | Import and register `TreeDrawer` hook |
| `assets/css/app.css` | Modify | Drawer and bottom sheet transition styles |
| `test/ancestry/people/person_graph_test.exs` | Modify | Tests for lateral traversal |
| `test/user_flows/family_graph_test.exs` | Modify | E2E tests for drawer + depth controls |
| `priv/gettext/es-UY/LC_MESSAGES/default.po` | Modify | Spanish translations |

---

### Task 1: Implement "other" (lateral) traversal in PersonGraph

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Test: `test/ancestry/people/person_graph_test.exs`

- [ ] **Step 1: Change default `other` to 1**

In `lib/ancestry/people/person_graph.ex`, change:

```elixir
@default_opts [ancestors: 2, descendants: 2, other: 0]
```

to:

```elixir
@default_opts [ancestors: 2, descendants: 2, other: 1]
```

Also update the `@doc` for `build/3` to remove "currently unused".

- [ ] **Step 2: Write failing tests for lateral traversal**

Add to `test/ancestry/people/person_graph_test.exs`:

```elixir
describe "lateral (other) traversal" do
  setup do
    family = family_fixture()
    org_id = family.organization_id

    # Build: Grandpa + Grandma -> Dad + Uncle
    #                           -> Dad + Mom -> Focus + Sibling
    {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "L"})
    {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "L"})
    {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "L"})
    {:ok, uncle} = People.create_person(family, %{given_name: "Uncle", surname: "L"})
    {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "L"})
    {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "L"})
    {:ok, sibling} = People.create_person(family, %{given_name: "Sibling", surname: "L"})
    {:ok, cousin} = People.create_person(family, %{given_name: "Cousin", surname: "L"})

    {:ok, _} = Relationships.create_relationship(grandpa, grandma, "married", %{})
    {:ok, _} = Relationships.create_relationship(grandpa, dad, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(grandma, dad, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(grandpa, uncle, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(grandma, uncle, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})
    {:ok, _} = Relationships.create_relationship(dad, focus, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(dad, sibling, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mom, sibling, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(uncle, cousin, "parent", %{role: "father"})

    %{
      family: family,
      grandpa: grandpa, grandma: grandma,
      dad: dad, uncle: uncle, mom: mom,
      focus: focus, sibling: sibling, cousin: cousin
    }
  end

  test "other=0 shows direct line only", ctx do
    graph = PersonGraph.build(ctx.focus, ctx.family.id, ancestors: 2, descendants: 0, other: 0)
    ids = person_ids(graph)

    assert MapSet.member?(ids, ctx.focus.id)
    assert MapSet.member?(ids, ctx.dad.id)
    assert MapSet.member?(ids, ctx.mom.id)
    refute MapSet.member?(ids, ctx.sibling.id)
    refute MapSet.member?(ids, ctx.uncle.id)
    refute MapSet.member?(ids, ctx.cousin.id)
  end

  test "other=1 shows siblings (parents' other children)", ctx do
    graph = PersonGraph.build(ctx.focus, ctx.family.id, ancestors: 2, descendants: 0, other: 1)
    ids = person_ids(graph)

    assert MapSet.member?(ids, ctx.sibling.id)
    refute MapSet.member?(ids, ctx.uncle.id)
    refute MapSet.member?(ids, ctx.cousin.id)
  end

  test "other=2 shows siblings and cousins", ctx do
    graph = PersonGraph.build(ctx.focus, ctx.family.id, ancestors: 2, descendants: 0, other: 2)
    ids = person_ids(graph)

    assert MapSet.member?(ids, ctx.sibling.id)
    assert MapSet.member?(ids, ctx.uncle.id)
    assert MapSet.member?(ids, ctx.cousin.id)
  end

  test "other is bounded by ancestors", ctx do
    # ancestors=1 means grandparents not loaded, so cousins can't appear
    graph = PersonGraph.build(ctx.focus, ctx.family.id, ancestors: 1, descendants: 0, other: 3)
    ids = person_ids(graph)

    assert MapSet.member?(ids, ctx.sibling.id)
    refute MapSet.member?(ids, ctx.uncle.id)
    refute MapSet.member?(ids, ctx.cousin.id)
  end

  test "lateral descendants are bounded by max_descendants relative to focus", ctx do
    # Uncle's child (cousin) is at gen 0 (same as focus). With descendants=0,
    # the cousin should still appear because they're at the focus gen level.
    # But cousin's children (if any) should NOT appear.
    graph = PersonGraph.build(ctx.focus, ctx.family.id, ancestors: 2, descendants: 0, other: 2)
    ids = person_ids(graph)

    assert MapSet.member?(ids, ctx.cousin.id)
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/ancestry/people/person_graph_test.exs --seed 0`
Expected: tests about `other=1` and `other=2` should fail (laterals not traversed yet).

- [ ] **Step 4: Implement `traverse_laterals/4` in PersonGraph**

In `lib/ancestry/people/person_graph.ex`, add the lateral traversal phase. In `build/3`, after `traverse_descendants` and before `layout_grid`:

```elixir
# Walk lateral relatives (siblings, cousins, etc.)
max_other = min(opts[:other], max_ancestors)
state = traverse_laterals(state, max_other, max_descendants, graph)
```

Then add the private function:

```elixir
defp traverse_laterals(state, 0, _max_descendants, _graph), do: state

defp traverse_laterals(state, max_other, max_descendants, graph) do
  # For each ancestor at generation g (where g <= max_other),
  # find their children not already in the graph and add them.
  focus_id = state.focus_id

  # Collect ancestors by generation
  ancestors_by_gen =
    state.visited
    |> Enum.filter(fn {id, gen} -> gen > 0 and id != focus_id end)
    |> Enum.group_by(fn {_id, gen} -> gen end, fn {id, _gen} -> id end)

  # Process from closest ancestors outward (gen 1 first, then gen 2, etc.)
  Enum.reduce(1..max_other, state, fn gen, acc ->
    ancestor_ids = Map.get(ancestors_by_gen, gen, [])

    Enum.reduce(ancestor_ids, acc, fn ancestor_id, acc2 ->
      children = FamilyGraph.children(graph, ancestor_id)

      # Filter to children not already in the graph
      new_children = Enum.reject(children, &Map.has_key?(acc2.visited, &1.id))
      child_gen = gen - 1

      Enum.reduce(new_children, acc2, fn child, acc3 ->
        # The depth from focus for this lateral child.
        # child_gen is positive (e.g., gen 1 = parents' level, gen 0 = focus level).
        # Convert to depth: depth = max(0, -child_gen) for levels below focus,
        # but laterals at or above focus level start at depth 0.
        depth = max(0, -child_gen)
        at_limit = depth >= max_descendants

        has_more_down = at_limit and FamilyGraph.has_children?(graph, child.id)
        acc3 = %{acc3 | visited: Map.put(acc3.visited, child.id, child_gen)}
        acc3 = add_entry(acc3, child, child_gen, false, false, has_more_down)

        # Add parent->child edge
        acc3 = add_parent_child_edge(acc3, ancestor_id, child.id, false)

        if at_limit do
          # At limit: add partner info but don't recurse
          add_at_limit_partners(acc3, child, child_gen, graph)
        else
          # Traverse lateral's descendants using existing function
          # Note: traverse_descendants(person, depth, max_descendants, graph, state)
          traverse_descendants(child, depth, max_descendants, graph, acc3)
        end
      end)
    end)
  end)
end


# Note: traverse_lateral_descendants was removed — we call traverse_descendants
# directly with the correct depth argument (see reduce above).
```

**Note:** This reuses the existing `traverse_descendants/5` for lateral children's subtrees, ensuring consistent behavior (partner grouping, duplication rules, at-limit handling).

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/ancestry/people/person_graph_test.exs --seed 0`
Expected: All tests pass.

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass. Existing tests with `other: 0` default may now include siblings — check and adjust if needed.

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Implement lateral (other) traversal in PersonGraph"
```

---

### Task 2: Read depth params in `handle_params` and update all URL patchers

**Files:**
- Modify: `lib/web/live/family_live/show.ex`

- [ ] **Step 1: Add depth assigns in `mount`**

In `lib/web/live/family_live/show.ex`, add after `assign(:graph, nil)`:

```elixir
|> assign(:tree_ancestors, 2)
|> assign(:tree_descendants, 2)
|> assign(:tree_other, 1)
|> assign(:tree_display, "partial")
|> assign(:partial_settings, %{ancestors: 2, descendants: 2, other: 1})
```

- [ ] **Step 2: Read depth params in `handle_params`**

Replace the current `handle_params/3` body. After parsing `focus_person`, add param reading:

```elixir
tree_ancestors = parse_depth_param(params, "ancestors", 2)
tree_descendants = parse_depth_param(params, "descendants", 2)
tree_other = parse_depth_param(params, "other", 1)
tree_display = if params["display"] == "complete", do: "complete", else: "partial"

{tree_ancestors, tree_descendants, tree_other} =
  if tree_display == "complete" do
    {20, 20, 20}
  else
    {tree_ancestors, tree_descendants, tree_other}
  end

# Clamp other to ancestors
tree_other = min(tree_other, tree_ancestors)

graph =
  if focus_person do
    PersonGraph.build(focus_person, socket.assigns.family_graph,
      ancestors: tree_ancestors,
      descendants: tree_descendants,
      other: tree_other
    )
  else
    nil
  end

partial_settings =
  if tree_display == "partial" do
    %{ancestors: tree_ancestors, descendants: tree_descendants, other: tree_other}
  else
    socket.assigns.partial_settings
  end

socket =
  socket
  |> assign(:focus_person, focus_person)
  |> assign(:graph, graph)
  |> assign(:tree_ancestors, tree_ancestors)
  |> assign(:tree_descendants, tree_descendants)
  |> assign(:tree_other, tree_other)
  |> assign(:tree_display, tree_display)
  |> assign(:partial_settings, partial_settings)
```

Add the private helper:

```elixir
defp parse_depth_param(params, key, default) do
  case params[key] do
    nil -> default
    val -> val |> String.to_integer() |> max(0) |> min(20)
  end
end
```

- [ ] **Step 3: Add helper to build family path with depth params**

Single helper that handles all cases — building paths with current socket assigns or with explicit override values:

```elixir
defp family_path(socket, person_id, overrides \\ %{}) do
  base = ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}"

  ancestors = Map.get(overrides, :ancestors, socket.assigns.tree_ancestors)
  descendants = Map.get(overrides, :descendants, socket.assigns.tree_descendants)
  other = Map.get(overrides, :other, socket.assigns.tree_other)
  display = Map.get(overrides, :display, socket.assigns.tree_display)

  params = %{}
  params = if person_id, do: Map.put(params, :person, person_id), else: params
  params = if ancestors != 2, do: Map.put(params, :ancestors, ancestors), else: params
  params = if descendants != 2, do: Map.put(params, :descendants, descendants), else: params
  params = if other != 1, do: Map.put(params, :other, other), else: params
  params = if display != "partial", do: Map.put(params, :display, display), else: params

  if params == %{}, do: base, else: "#{base}?#{URI.encode_query(params)}"
end
```

- [ ] **Step 4: Update `focus_person` event to preserve depth params**

Change the `push_patch` in the `"focus_person"` handler (line ~130) from:

```elixir
~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{socket.assigns.family.id}?person=#{id}"
```

to:

```elixir
family_path(socket, id)
```

- [ ] **Step 5: Update `handle_info({:focus_person, ...})` similarly**

Change the `push_patch` at line ~548 to use `family_path(socket, person_id)`.

- [ ] **Step 6: Update `refresh_graph` to pass depth opts**

In `refresh_graph/1`, change:

```elixir
PersonGraph.build(focus_person, family_graph)
```

to:

```elixir
PersonGraph.build(focus_person, family_graph,
  ancestors: socket.assigns.tree_ancestors,
  descendants: socket.assigns.tree_descendants,
  other: socket.assigns.tree_other
)
```

- [ ] **Step 7: Also update `"save"` event handler for family editing**

The `"save"` event at line ~171 calls `PersonGraph.build(person, socket.assigns.family_graph)` without depth opts. Update it similarly.

- [ ] **Step 8: Add slider change events**

```elixir
def handle_event("update_tree_depth", params, socket) do
  ancestors = parse_depth_param(params, "ancestors", socket.assigns.tree_ancestors)
  descendants = parse_depth_param(params, "descendants", socket.assigns.tree_descendants)
  other = parse_depth_param(params, "other", socket.assigns.tree_other)
  person_id = socket.assigns.focus_person && socket.assigns.focus_person.id

  {:noreply,
   push_patch(socket,
     to: family_path(socket, person_id, %{ancestors: ancestors, descendants: descendants, other: other})
   )}
end

def handle_event("toggle_display", %{"display" => display}, socket) do
  person_id = socket.assigns.focus_person && socket.assigns.focus_person.id

  case display do
    "complete" ->
      {:noreply,
       push_patch(socket,
         to: family_path(socket, person_id, %{ancestors: 20, descendants: 20, other: 20, display: "complete"})
       )}

    "partial" ->
      ps = socket.assigns.partial_settings
      {:noreply,
       push_patch(socket,
         to: family_path(socket, person_id, %{ancestors: ps.ancestors, descendants: ps.descendants, other: ps.other, display: "partial"})
       )}
  end
end
```

- [ ] **Step 9: Run `mix test` to verify nothing breaks**

- [ ] **Step 10: Commit**

```bash
git add lib/web/live/family_live/show.ex
git commit -m "Read tree depth params from URL and update all URL patchers"
```

---

### Task 3: Desktop drawer UI

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`
- Create: `assets/js/tree_drawer.js`
- Modify: `assets/js/app.js`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Create the `TreeDrawer` JS hook**

Create `assets/js/tree_drawer.js`:

```javascript
export const TreeDrawer = {
  mounted() {
    this.expanded = false
    this.panel = this.el.querySelector("[data-drawer-panel]")

    this.el.querySelector("[data-drawer-toggle]")?.addEventListener("click", () => {
      this.expanded = !this.expanded
      this.updateState()
    })
  },

  updateState() {
    if (!this.panel) return
    if (this.expanded) {
      this.panel.classList.remove("max-h-0", "opacity-0")
      this.panel.classList.add("max-h-[200px]", "opacity-100")
    } else {
      this.panel.classList.remove("max-h-[200px]", "opacity-100")
      this.panel.classList.add("max-h-0", "opacity-0")
    }
  },

  destroyed() {
    // Guard: mounted() may not have completed
    if (!this.panel) return
  }
}
```

- [ ] **Step 2: Register the hook in `app.js`**

In `assets/js/app.js`, add the import:

```javascript
import { TreeDrawer } from "./tree_drawer"
```

And add `TreeDrawer` to the hooks object on line 61.

- [ ] **Step 3: Add drawer CSS transitions in `app.css`**

Add to `assets/css/app.css`:

```css
/* Tree drawer transitions */
[data-drawer-panel] {
  transition: max-height 200ms ease-out, opacity 150ms ease-out;
  overflow: hidden;
}
```

- [ ] **Step 4: Add desktop drawer markup to `show.html.heex`**

Inside the `#tree-canvas` div, after the `graph_canvas` / empty-state block and before the closing `</div>`, add the desktop drawer (hidden on mobile):

```heex
<%!-- Desktop tree depth drawer --%>
<div
  :if={@graph}
  id="tree-drawer"
  phx-hook="TreeDrawer"
  class="hidden lg:block absolute bottom-0 left-0 right-0 bg-ds-surface-low border-t border-ds-outline-variant/30"
  {test_id("tree-drawer")}
>
  <%!-- Collapsed bar: summary + toggle --%>
  <button
    type="button"
    data-drawer-toggle
    class="w-full flex items-center justify-between px-5 py-2 hover:bg-ds-surface-high transition-colors"
    aria-label={gettext("Toggle tree controls")}
  >
    <div class="flex items-center gap-3 text-sm">
      <span class="text-ds-primary font-ds-body font-medium">
        {if @tree_display == "complete", do: gettext("Complete Tree"), else: gettext("Partial Tree")}
      </span>
      <span class="w-px h-4 bg-ds-outline-variant/30"></span>
      <span class="text-ds-on-surface-variant font-ds-body text-xs">
        {gettext("Parents")} <span class="text-ds-primary font-semibold">{@tree_ancestors}</span>
      </span>
      <span class="text-ds-on-surface-variant font-ds-body text-xs">
        {gettext("Children")} <span class="text-ds-primary font-semibold">{@tree_descendants}</span>
      </span>
      <span class="text-ds-on-surface-variant font-ds-body text-xs">
        {gettext("Other")} <span class="text-ds-primary font-semibold">{@tree_other}</span>
      </span>
    </div>
    <.icon name="hero-chevron-up" class="size-4 text-ds-on-surface-variant" />
  </button>

  <%!-- Expanded panel --%>
  <div data-drawer-panel class="max-h-0 opacity-0">
    <div class="px-5 py-4 border-t border-ds-outline-variant/20 flex items-start gap-6">
      <%!-- Display toggle --%>
      <div class="flex-shrink-0">
        <div class="text-[10px] text-ds-on-surface-variant uppercase tracking-wider mb-2 font-ds-body">
          {gettext("Display")}
        </div>
        <div class="flex bg-ds-surface-card rounded-md p-0.5">
          <button
            type="button"
            phx-click="toggle_display"
            phx-value-display="partial"
            class={"px-3 py-1.5 rounded text-xs font-ds-body font-medium transition-colors " <>
              if(@tree_display == "partial", do: "bg-ds-primary text-ds-on-primary", else: "text-ds-on-surface-variant hover:text-ds-on-surface")}
          >
            {gettext("Partial Tree")}
          </button>
          <button
            type="button"
            phx-click="toggle_display"
            phx-value-display="complete"
            class={"px-3 py-1.5 rounded text-xs font-ds-body font-medium transition-colors " <>
              if(@tree_display == "complete", do: "bg-ds-primary text-ds-on-primary", else: "text-ds-on-surface-variant hover:text-ds-on-surface")}
          >
            {gettext("Complete Tree")}
          </button>
        </div>
      </div>

      <span class="w-px h-12 bg-ds-outline-variant/20 flex-shrink-0 mt-4"></span>

      <%!-- Sliders (hidden when complete) --%>
      <form :if={@tree_display == "partial"} phx-change="update_tree_depth" class="flex-1 flex gap-6">
        <.tree_slider
          label={gettext("Parents")}
          name="ancestors"
          value={@tree_ancestors}
          max={20}
        />
        <.tree_slider
          label={gettext("Children")}
          name="descendants"
          value={@tree_descendants}
          max={20}
        />
        <.tree_slider
          label={gettext("Other")}
          name="other"
          value={@tree_other}
          max={@tree_ancestors}
        />
      </form>
      <div :if={@tree_display == "complete"} class="flex-1 flex items-center mt-4">
        <span class="text-sm text-ds-on-surface-variant font-ds-body">
          {gettext("Showing all generations")}
        </span>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Add the `tree_slider` function component**

In `lib/web/live/family_live/show.html.heex` (or better, in `show.ex` as a private component), add:

```elixir
attr :label, :string, required: true
attr :name, :string, required: true
attr :value, :integer, required: true
attr :max, :integer, required: true

defp tree_slider(assigns) do
  ~H"""
  <div class="flex-1 min-w-[100px]">
    <div class="flex justify-between mb-1.5">
      <span class="text-xs text-ds-on-surface font-ds-body">{@label}</span>
      <span class="text-xs text-ds-primary font-ds-body font-semibold bg-ds-surface-card rounded px-1.5">
        {@value}
      </span>
    </div>
    <input
      type="range"
      name={@name}
      value={@value}
      min="0"
      max={@max}
      step="1"
      phx-debounce="200"
      class="w-full h-1 bg-ds-outline-variant/30 rounded-full appearance-none cursor-pointer accent-ds-primary"
    />
  </div>
  """
end
```

- [ ] **Step 6: Run the dev server and verify desktop drawer works**

Run: `iex -S mix phx.server`
Check:
- Collapsed bar appears at bottom of tree view
- Clicking expands to show controls
- Sliders change URL params and rebuild tree
- "Complete Tree" toggle works
- Focus person scroll-to works after rebuild

- [ ] **Step 7: Commit**

```bash
git add assets/js/tree_drawer.js assets/js/app.js assets/css/app.css \
      lib/web/live/family_live/show.html.heex lib/web/live/family_live/show.ex
git commit -m "Add desktop tree depth drawer with sliders"
```

---

### Task 4: Mobile header button + bottom sheet

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`
- Modify: `lib/web/live/family_live/show.ex`

- [ ] **Step 1: Add `show_mobile_tree_sheet` assign in mount**

```elixir
|> assign(:show_mobile_tree_sheet, false)
```

- [ ] **Step 2: Add handle_events for mobile sheet**

```elixir
def handle_event("open_mobile_tree_sheet", _, socket) do
  {:noreply, assign(socket, :show_mobile_tree_sheet, true)}
end

def handle_event("close_mobile_tree_sheet", _, socket) do
  {:noreply, assign(socket, :show_mobile_tree_sheet, false)}
end
```

- [ ] **Step 3: Add "Tree" button to mobile nav drawer `page_actions`**

In `show.html.heex`, inside the `<:page_actions>` slot (around line 131), add:

```heex
<.nav_action
  :if={@graph}
  icon="hero-adjustments-horizontal"
  label={gettext("Tree View")}
  phx-click={toggle_nav_drawer() |> JS.push("open_mobile_tree_sheet")}
/>
```

- [ ] **Step 4: Add mobile bottom sheet modal markup**

After the other modals in `show.html.heex`, add:

```heex
<%!-- Mobile Tree Depth Sheet --%>
<%= if @show_mobile_tree_sheet do %>
  <div
    class="fixed inset-0 z-50 flex items-end justify-center lg:hidden"
    phx-window-keydown="close_mobile_tree_sheet"
    phx-key="Escape"
  >
    <div
      class="absolute inset-0 bg-black/60 backdrop-blur-sm"
      phx-click="close_mobile_tree_sheet"
    />
    <div
      class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full rounded-t-2xl"
      role="dialog"
      aria-modal="true"
      aria-labelledby="mobile-tree-title"
      {test_id("mobile-tree-sheet")}
    >
      <%!-- Drag handle --%>
      <div class="flex justify-center pt-3 pb-1">
        <div class="w-9 h-1 bg-ds-outline-variant/40 rounded-full"></div>
      </div>
      <%!-- Header --%>
      <div class="flex items-center justify-between px-5 pb-3 border-b border-ds-outline-variant/20">
        <h2 id="mobile-tree-title" class="text-base font-ds-heading font-semibold text-ds-on-surface">
          {gettext("Tree View")}
        </h2>
        <button
          type="button"
          phx-click="close_mobile_tree_sheet"
          class="text-sm text-ds-primary font-ds-body font-medium"
        >
          {gettext("Done")}
        </button>
      </div>
      <%!-- Display toggle --%>
      <div class="px-5 pt-4 pb-3">
        <div class="text-[10px] text-ds-on-surface-variant uppercase tracking-wider mb-2 font-ds-body">
          {gettext("Display")}
        </div>
        <div class="flex bg-ds-surface-low rounded-lg p-0.5">
          <button
            type="button"
            phx-click="toggle_display"
            phx-value-display="partial"
            class={"flex-1 text-center py-2 rounded-md text-sm font-ds-body font-medium transition-colors " <>
              if(@tree_display == "partial", do: "bg-ds-primary text-ds-on-primary", else: "text-ds-on-surface-variant")}
          >
            {gettext("Partial Tree")}
          </button>
          <button
            type="button"
            phx-click="toggle_display"
            phx-value-display="complete"
            class={"flex-1 text-center py-2 rounded-md text-sm font-ds-body font-medium transition-colors " <>
              if(@tree_display == "complete", do: "bg-ds-primary text-ds-on-primary", else: "text-ds-on-surface-variant")}
          >
            {gettext("Complete Tree")}
          </button>
        </div>
      </div>
      <%!-- Sliders --%>
      <form :if={@tree_display == "partial"} phx-change="update_tree_depth" class="px-5 pb-6 space-y-5">
        <.tree_slider label={gettext("Parents")} name="ancestors" value={@tree_ancestors} max={20} />
        <.tree_slider label={gettext("Children")} name="descendants" value={@tree_descendants} max={20} />
        <.tree_slider label={gettext("Other")} name="other" value={@tree_other} max={@tree_ancestors} />
      </form>
      <div :if={@tree_display == "complete"} class="px-5 pb-6">
        <span class="text-sm text-ds-on-surface-variant font-ds-body">
          {gettext("Showing all generations")}
        </span>
      </div>
      <%!-- Bottom safe area --%>
      <div class="h-6"></div>
    </div>
  </div>
<% end %>
```

- [ ] **Step 5: Test on mobile viewport in browser**

Open dev tools, set viewport to mobile (375px), verify:
- "Tree View" button appears in the mobile nav drawer actions
- Tapping it opens the bottom sheet
- Sliders work and rebuild the tree behind the sheet
- "Done" button closes the sheet

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "Add mobile tree depth bottom sheet"
```

---

### Task 5: Gettext translations

**Files:**
- Modify: `priv/gettext/es-UY/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract new gettext strings**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Fill in Spanish translations**

Open `priv/gettext/es-UY/LC_MESSAGES/default.po` and translate the new entries:

| English | Spanish |
|---------|---------|
| Partial Tree | Árbol Parcial |
| Complete Tree | Árbol Completo |
| Parents | Padres |
| Children | Hijos |
| Other | Otros |
| Showing all generations | Mostrando todas las generaciones |
| Tree View | Vista del Árbol |
| Done | Listo |
| Toggle tree controls | Alternar controles del árbol |
| Display | Mostrar |

- [ ] **Step 3: Commit**

```bash
git add priv/gettext/
git commit -m "Add Spanish translations for tree depth controls"
```

---

### Task 6: E2E tests

**Files:**
- Modify: `test/user_flows/family_graph_test.exs`

- [ ] **Step 1: Add E2E tests for depth controls**

Add to `test/user_flows/family_graph_test.exs`:

```elixir
# Tree depth controls
#
# Given a family with a graph rendered
# When the user visits the family show page
# Then the collapsed tree drawer is visible (desktop)
#
# When the user changes ancestor depth via URL params
# Then the graph rebuilds with the new depth
#
# When the user changes display to "complete"
# Then all depths are set to 20

test "URL depth params control graph depth", %{
  conn: conn,
  family: family,
  org: org,
  alice: alice
} do
  conn = log_in_e2e(conn)

  # Visit with custom depth params
  conn =
    conn
    |> visit(~p"/org/#{org.id}/families/#{family.id}?person=#{alice.id}&ancestors=3&descendants=1")

  # Verify graph renders
  conn |> assert_has(test_id("graph-canvas"))

  # Verify the drawer shows the correct values
  conn |> assert_has(test_id("tree-drawer"))
end

test "complete display mode shows all generations", %{
  conn: conn,
  family: family,
  org: org,
  alice: alice
} do
  conn = log_in_e2e(conn)

  conn =
    conn
    |> visit(~p"/org/#{org.id}/families/#{family.id}?person=#{alice.id}&display=complete")

  # Verify graph renders
  conn |> assert_has(test_id("graph-canvas"))
end
```

- [ ] **Step 2: Run E2E tests**

Run: `mix test test/user_flows/family_graph_test.exs`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/family_graph_test.exs
git commit -m "Add E2E tests for tree depth controls"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run `mix precommit`**

Run: `mix precommit`
Expected: compile (warnings-as-errors) + format + tests all pass.

- [ ] **Step 2: Manual testing checklist**

- [ ] Desktop: collapsed drawer shows correct summary
- [ ] Desktop: expanding drawer shows sliders
- [ ] Desktop: dragging a slider rebuilds tree live
- [ ] Desktop: "Complete Tree" toggle sets all to 20, hides sliders
- [ ] Desktop: "Partial Tree" restores previous values
- [ ] Desktop: clicking a person in tree preserves depth params
- [ ] Desktop: "Other" slider max is clamped to ancestors value
- [ ] Mobile: "Tree View" action appears in nav drawer
- [ ] Mobile: bottom sheet opens with correct controls
- [ ] Mobile: sliders work and tree updates behind sheet
- [ ] Mobile: "Done" closes the sheet
- [ ] URL with depth params is shareable and survives refresh
- [ ] Default URL (no params) uses defaults: ancestors=2, descendants=2, other=1

- [ ] **Step 3: Commit any final fixes**
