# Print Family Tree (Indented List) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the grid-based print page with an indented list that always fits on paper — pure HTML, no SVG, no grid coordinates.

**Architecture:** A new `PrintTree` module builds a nested tree structure by walking the `FamilyGraph` upward from the focus person's oldest ancestors and downward through descendants. A `PrintTreeComponent` renders it as recursive HEEx with indentation, vertical border lines, and gender-colored squares. The existing print LiveView, route, layout, AutoPrint hook, and print button are reused as-is.

**Tech Stack:** Phoenix LiveView, FamilyGraph API, recursive HEEx components

**Spec:** `docs/plans/2026-04-24-print-family-tree-design.md`

---

### Task 1: Create `PrintTree` module — builds nested tree from FamilyGraph

**Files:**
- Create: `lib/ancestry/people/print_tree.ex`

This module walks the `FamilyGraph` to produce a nested tree structure for printing. It starts from the focus person, walks UP to find the oldest ancestors (respecting depth limits), then walks DOWN from those ancestors to produce the indented hierarchy.

- [ ] **Step 1: Create the module**

```elixir
defmodule Ancestry.People.PrintTree do
  @moduledoc """
  Builds a nested tree structure from a FamilyGraph for print rendering.

  Walks upward from the focus person to find root ancestors, then downward
  to produce a nested list of person entries with their partners and children.
  """

  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person

  defstruct [:focus_person_id, :roots]

  @doc """
  Builds a print tree centered on the focus person.

  Options:
    - `ancestors:` — generations upward (default 2)
    - `descendants:` — generations downward from focus (default 2)
    - `other:` — lateral expansion depth (default 1)
  """
  def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts \\ []) do
    ancestors = Keyword.get(opts, :ancestors, 2)
    descendants = Keyword.get(opts, :descendants, 2)
    other = Keyword.get(opts, :other, 1)

    # Find the root ancestors by walking up from the focus person
    roots = find_roots(graph, focus_person.id, ancestors)

    # Build the tree downward from each root
    seen = MapSet.new()

    {tree_roots, _seen} =
      Enum.map_reduce(roots, seen, fn root_id, seen ->
        build_person_entry(graph, root_id, focus_person.id, seen, descendants, other, 0, ancestors)
      end)

    %__MODULE__{focus_person_id: focus_person.id, roots: tree_roots}
  end

  # Walk upward from the focus person to find the oldest ancestors within depth.
  defp find_roots(graph, person_id, max_depth) do
    do_find_roots(graph, [person_id], 0, max_depth, MapSet.new())
  end

  defp do_find_roots(_graph, person_ids, depth, max_depth, _visited) when depth >= max_depth do
    person_ids
  end

  defp do_find_roots(graph, person_ids, depth, max_depth, visited) do
    # For each person, get their parents. If they have parents and we haven't
    # exceeded depth, keep walking up. Otherwise, they're a root.
    {roots, next_level, visited} =
      Enum.reduce(person_ids, {[], [], visited}, fn pid, {roots_acc, next_acc, vis} ->
        if MapSet.member?(vis, pid) do
          {roots_acc, next_acc, vis}
        else
          vis = MapSet.put(vis, pid)
          parents = FamilyGraph.parents(graph, pid)
          parent_ids = Enum.map(parents, fn {p, _r} -> p.id end)

          if parent_ids == [] do
            {[pid | roots_acc], next_acc, vis}
          else
            {roots_acc, parent_ids ++ next_acc, vis}
          end
        end
      end)

    if next_level == [] do
      Enum.reverse(roots)
    else
      upper_roots = do_find_roots(graph, Enum.uniq(next_level), depth + 1, max_depth, visited)
      Enum.reverse(roots) ++ upper_roots
    end
  end

  # Build a person entry with their partners and children.
  # Returns {entry, seen} where seen tracks visited person IDs to prevent duplicates.
  defp build_person_entry(graph, person_id, focus_id, seen, max_desc, max_other, depth_from_focus, max_ancestors) do
    if MapSet.member?(seen, person_id) do
      person = FamilyGraph.fetch_person!(graph, person_id)
      entry = %{type: :back_ref, person: person}
      {entry, seen}
    else
      person = FamilyGraph.fetch_person!(graph, person_id)
      seen = MapSet.put(seen, person_id)
      is_focus = person_id == focus_id

      # Determine if this person is on the direct ancestor path to focus
      # (affects whether we expand descendants for lateral branches)
      on_direct_path = is_ancestor_of_focus?(graph, person_id, focus_id, max_ancestors)

      # Get all partners with their shared children
      all_partners = FamilyGraph.all_partners(graph, person_id)
      solo_children = FamilyGraph.solo_children(graph, person_id)

      # Build partner sub-entries
      {partner_entries, seen} =
        Enum.map_reduce(all_partners, seen, fn {partner, rel}, seen ->
          shared_children = FamilyGraph.children_of_pair(graph, person_id, partner.id)

          # Build children entries recursively
          {children_entries, seen} =
            if should_expand_children?(is_focus, on_direct_path, depth_from_focus, max_desc, max_other) do
              Enum.map_reduce(shared_children, seen, fn child, seen ->
                child_depth = if is_focus, do: 1, else: depth_from_focus + 1
                build_person_entry(graph, child.id, focus_id, seen, max_desc, max_other, child_depth, max_ancestors)
              end)
            else
              {[], seen}
            end

          entry = %{
            type: :partner,
            person: partner,
            relationship_type: rel.type,
            children: children_entries
          }

          {entry, seen}
        end)

      # Build solo children entries
      {solo_entries, seen} =
        if should_expand_children?(is_focus, on_direct_path, depth_from_focus, max_desc, max_other) do
          Enum.map_reduce(solo_children, seen, fn child, seen ->
            child_depth = if is_focus, do: 1, else: depth_from_focus + 1
            build_person_entry(graph, child.id, focus_id, seen, max_desc, max_other, child_depth, max_ancestors)
          end)
        else
          {[], seen}
        end

      entry = %{
        type: :person,
        person: person,
        is_focus: is_focus,
        partners: partner_entries,
        solo_children: solo_entries
      }

      {entry, seen}
    end
  end

  defp should_expand_children?(true, _on_direct, _depth, _max_desc, _max_other), do: true
  defp should_expand_children?(_is_focus, true, _depth, _max_desc, _max_other), do: true
  defp should_expand_children?(_is_focus, _on_direct, depth, max_desc, _max_other) when depth < max_desc, do: true
  defp should_expand_children?(_, _, _, _, _), do: false

  # Check if person_id is an ancestor of focus_id (within max_depth).
  defp is_ancestor_of_focus?(graph, person_id, focus_id, max_depth) do
    person_id == focus_id or do_is_ancestor?(graph, focus_id, person_id, 0, max_depth)
  end

  defp do_is_ancestor?(_graph, _current_id, _target_id, depth, max_depth) when depth >= max_depth, do: false

  defp do_is_ancestor?(graph, current_id, target_id, depth, max_depth) do
    parents = FamilyGraph.parents(graph, current_id)

    Enum.any?(parents, fn {parent, _rel} ->
      parent.id == target_id or do_is_ancestor?(graph, parent.id, target_id, depth + 1, max_depth)
    end)
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/ancestry/people/print_tree.ex
git commit -m "Add PrintTree module for indented list print layout"
```

---

### Task 2: Create `PrintTreeComponent` — renders the indented list

**Files:**
- Create: `lib/web/live/family_live/print_tree_component.ex`
- Delete: `lib/web/live/family_live/print_graph_component.ex`

- [ ] **Step 1: Create the component**

```elixir
defmodule Web.FamilyLive.PrintTreeComponent do
  use Web, :html

  alias Ancestry.People.Person

  @doc "Renders the full print tree as an indented list."
  attr :tree, :map, required: true

  def print_tree(assigns) do
    ~H"""
    <div class="print-tree font-['Inter',system-ui,sans-serif] text-[11.5px] text-[#1a1a1a] leading-[1.9]">
      <%= for root <- @tree.roots do %>
        <.tree_entry entry={root} focus_person_id={@tree.focus_person_id} />
      <% end %>
    </div>
    """
  end

  # --- Entry dispatcher ---

  defp tree_entry(%{entry: %{type: :back_ref}} = assigns) do
    ~H"""
    <div class="text-gray-400 italic text-[10px]">
      &rarr; {Person.display_name(@entry.person)} ({gettext("see above")})
    </div>
    """
  end

  defp tree_entry(%{entry: %{type: :person}} = assigns) do
    ~H"""
    <div>
      <%!-- Person line --%>
      <div class={if @entry.is_focus, do: "bg-blue-50 -mx-2 px-2 py-0.5 rounded border-l-[3px] border-l-blue-500", else: ""}>
        <.gender_icon gender={@entry.person.gender} />
        <span class={if @entry.is_focus, do: "font-bold text-blue-700", else: "font-semibold"}>
          {Person.display_name(@entry.person)}
        </span>
        <.life_span person={@entry.person} />
      </div>

      <%!-- Partners and their children --%>
      <%= if @entry.partners != [] or @entry.solo_children != [] do %>
        <div class="ml-6 border-l-[1.5px] border-gray-200 pl-3">
          <%= for partner_entry <- @entry.partners do %>
            <.partner_block entry={partner_entry} focus_person_id={@focus_person_id} />
          <% end %>

          <%!-- Solo children --%>
          <%= if @entry.solo_children != [] do %>
            <div class="text-gray-400 italic text-[10px] mt-1">{gettext("no known partner")}:</div>
            <%= for child <- @entry.solo_children do %>
              <.tree_entry entry={child} focus_person_id={@focus_person_id} />
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Partner block ---

  defp partner_block(assigns) do
    ~H"""
    <div>
      <%!-- Partner line with relationship type --%>
      <div class="text-gray-400 text-[10px]">
        <.gender_icon gender={@entry.person.gender} />
        <em>{relationship_label(@entry.relationship_type)}</em>
        <strong class="text-gray-600">{Person.display_name(@entry.person)}</strong>
        <.life_span person={@entry.person} />
      </div>

      <%!-- Children of this partnership --%>
      <%= if @entry.children != [] do %>
        <div class="ml-6 border-l-[1.5px] border-gray-200 pl-3">
          <%= for child <- @entry.children do %>
            <.tree_entry entry={child} focus_person_id={@focus_person_id} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp gender_icon(assigns) do
    ~H"""
    <span class={["text-[7px]", gender_color(@gender)]}>&#9632;</span>
    """
  end

  defp life_span(assigns) do
    ~H"""
    <span class="text-gray-400 text-[10px]">
      <%= cond do %>
        <% @person.birth_year && @person.deceased -> %>
          ({@person.birth_year}&ndash;{@person.death_year || "?"})
        <% @person.birth_year -> %>
          ({@person.birth_year})
        <% true -> %>
      <% end %>
    </span>
    """
  end

  defp gender_color("male"), do: "text-blue-400"
  defp gender_color("female"), do: "text-pink-400"
  defp gender_color(_), do: "text-gray-400"

  defp relationship_label("married"), do: gettext("married to")
  defp relationship_label("relationship"), do: gettext("partner of")
  defp relationship_label("divorced"), do: gettext("divorced from")
  defp relationship_label("separated"), do: gettext("separated from")
  defp relationship_label(_), do: gettext("partner of")
end
```

- [ ] **Step 2: Delete the old grid component**

```bash
rm lib/web/live/family_live/print_graph_component.ex
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: may fail because `print.ex` still imports `PrintGraphComponent` — that's fixed in the next task.

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/print_tree_component.ex
git rm lib/web/live/family_live/print_graph_component.ex
git commit -m "Add PrintTreeComponent, remove PrintGraphComponent"
```

---

### Task 3: Update Print LiveView and template

**Files:**
- Modify: `lib/web/live/family_live/print.ex`
- Modify: `lib/web/live/family_live/print.html.heex`

- [ ] **Step 1: Rewrite `print.ex`**

Replace the entire content of `print.ex` with:

```elixir
defmodule Web.FamilyLive.Print do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.PrintTree
  alias Ancestry.Relationships

  import Web.FamilyLive.PrintTreeComponent

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

    tree =
      if focus_person do
        PrintTree.build(focus_person, socket.assigns.family_graph,
          ancestors: tree_ancestors,
          descendants: tree_descendants,
          other: tree_other
        )
      end

    {:noreply, assign(socket, :tree, tree)}
  end

  defp parse_depth(params, key, default) do
    case Integer.parse(params[key] || "") do
      {n, _} when n >= 1 and n <= 20 -> n
      _ -> default
    end
  end
end
```

- [ ] **Step 2: Rewrite the template**

Replace the entire content of `print.html.heex` with:

```heex
<Layouts.print flash={@flash}>
  <h1 class="text-2xl font-bold text-black text-center mb-6">
    {@family.name}
  </h1>

  <%= if @tree do %>
    <div id="print-page" phx-hook="AutoPrint">
      <.print_tree tree={@tree} />
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
git commit -m "Switch print page from grid to indented list"
```

---

### Task 4: Update CLAUDE.md

**Files:**
- Modify: `lib/web/live/family_live/CLAUDE.md`

- [ ] **Step 1: Update the CLAUDE.md**

Replace the entire content with:

```markdown
# Family Live

## Print page

The family tree has a dedicated print page (`print.ex` + `print.html.heex`) that opens in a new tab with an indented list layout.

- `PrintTreeComponent` renders the tree as an indented hierarchy with vertical border lines — keep this component separate from `GraphComponent` (the interactive grid view)
- `PrintTree` (in `lib/ancestry/people/print_tree.ex`) walks the `FamilyGraph` to produce a nested tree structure — it does NOT use `PersonGraph` or grid coordinates
- Both the print page and show page use the same underlying `FamilyGraph` data — changes to family data loading apply to both automatically
- The printing page and the show page must be kept in sync conceptually — if new relationship types are added or the FamilyGraph API changes, both pages must be updated accordingly

## Pages

- **`show.ex` / `show.html.heex`** — Interactive family tree view with CSS grid, SVG connectors, photos, hover effects, depth controls, side panel, and navigation. Uses `PersonGraph` for grid coordinates and `GraphConnector` JS hook for SVG.
- **`print.ex` / `print.html.heex`** — Print-optimized indented list view. Uses `PrintTree` to walk `FamilyGraph` directly. Pure HTML text, no SVG, no JS (except `AutoPrint` to trigger print dialog). Always fits on paper.
```

- [ ] **Step 2: Commit**

```bash
git add lib/web/live/family_live/CLAUDE.md
git commit -m "Update CLAUDE.md for indented list print approach"
```

---

### Task 5: Verification

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: all checks pass

- [ ] **Step 2: Manual test**

1. Start dev server: `iex -S mix phx.server`
2. Navigate to a family with a tree
3. Open the meatball menu → click "Print tree"
4. Verify: new tab opens with family name + indented list
5. Verify: focus person is highlighted in blue
6. Verify: partners appear on separate lines with relationship labels
7. Verify: children are indented under their parent's partner block
8. Verify: back-references appear for duplicate people (if applicable)
9. Verify: print dialog auto-opens
10. Verify: content fits within A4 landscape (no clipping!)
11. Verify: vertical border lines show parent-child relationships
