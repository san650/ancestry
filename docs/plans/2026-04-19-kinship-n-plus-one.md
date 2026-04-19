# Fix Kinship N+1 Queries (Blood + In-Law)

**Date:** 2026-04-19
**Status:** Design approved — awaiting implementation plan
**Branch:** `kingship-spanish`
**Related:** `docs/plans/2026-04-16-treeview-n-plus-one.md` (FamilyGraph origin)

## Problem

`Kinship.calculate/2` emits ~20-50 DB queries per blood-kinship calculation (BFS calls `Relationships.get_parents` per visited node, then `People.get_person!` per path node). `InLaw.calculate/2` is worse: it runs `get_all_partners` + multiple `build_ancestor_map` calls (one per partner of A and B), plus `get_person!` per path node — easily 50-100+ queries per calculation.

Every selector change, swap, or param-driven recalculation re-emits the full fan-out. `KinshipLive` already builds a `FamilyGraph` in mount (2 queries), but `Kinship.calculate/3` doesn't exist yet — `kinship.ex` only has the 2-arity, causing a compilation warning.

The TreeView N+1 plan (Task 5) covers blood kinship migration but **omits InLaw entirely**.

## Goal

Take blood kinship from ~20-50 queries per `calculate` to **0** (after a 2-query graph load). Take in-law kinship from ~50-100+ queries per `calculate` to **0**. Restructure `Kinship` into an orchestrator with clean submodules. Rename label modules for consistency. Preserve all current behavior.

## Architecture

### Module structure after refactor

```
Ancestry.Kinship                              # Orchestrator + shared primitives
├── calculate/3                               # Blood → InLaw fallback
├── build_ancestor_map/2                      # Shared graph-aware BFS
├── dna_percentage/3                          # Pure math, unchanged
└── %Kinship{} struct

Ancestry.Kinship.Blood                        # NEW — extracted from Kinship
└── calculate/3                               # BFS → MRCA → classify → path

Ancestry.Kinship.InLaw                        # MODIFIED — accepts graph
├── calculate/3                               # Partner-hop → BFS → classify → path
└── %InLaw{} struct

Ancestry.Kinship.BloodRelationshipLabel       # RENAMED from Label
Ancestry.Kinship.InLawRelationshipLabel       # RENAMED from InLawLabel

Ancestry.People.FamilyGraph                   # MODIFIED — 2 new lookups
├── all_partners/2                            # NEW
└── partner_relationship/3                    # NEW
```

### `Kinship` — orchestrator + shared primitives

`calculate/3` becomes a thin orchestrator that tries blood first, falls back to in-law:

```elixir
def calculate(a_id, b_id, _graph) when a_id == b_id, do: {:error, :same_person}

def calculate(a_id, b_id, %FamilyGraph{} = graph) do
  case Blood.calculate(a_id, b_id, graph) do
    {:ok, _} = result ->
      result

    {:error, :no_common_ancestor} ->
      case InLaw.calculate(a_id, b_id, graph) do
        {:ok, _} = result -> result
        {:error, _} -> {:error, :no_relationship}
      end
  end
end
```

`build_ancestor_map/2` stays in `Kinship` as a shared primitive used by both `Blood` and `InLaw`:

```elixir
def build_ancestor_map(person_id, %FamilyGraph{} = graph) do
  initial = %{person_id => {0, [person_id]}}
  bfs_expand([person_id], initial, 1, graph)
end

defp bfs_expand(_frontier, ancestors, depth, _graph) when depth > @max_depth, do: ancestors
defp bfs_expand([], ancestors, _depth, _graph), do: ancestors

defp bfs_expand(frontier, ancestors, depth, graph) do
  next_frontier =
    frontier
    |> Enum.flat_map(fn person_id ->
      FamilyGraph.parents(graph, person_id)
      |> Enum.map(fn {parent, _rel} -> {parent.id, person_id} end)
    end)
    |> Enum.reject(fn {parent_id, _child_id} -> Map.has_key?(ancestors, parent_id) end)

  new_ancestors =
    Enum.reduce(next_frontier, ancestors, fn {parent_id, child_id}, acc ->
      {_child_depth, child_path} = Map.fetch!(acc, child_id)
      Map.put(acc, parent_id, {depth, child_path ++ [parent_id]})
    end)

  new_frontier_ids =
    next_frontier
    |> Enum.map(fn {parent_id, _} -> parent_id end)
    |> Enum.uniq()

  bfs_expand(new_frontier_ids, new_ancestors, depth + 1, graph)
end
```

`dna_percentage/3` and the `%Kinship{}` struct stay as-is (pure math, no DB dependency).

Old arities removed: `calculate/2`, `build_ancestor_map/1`.

### `Kinship.Blood` — new module, extracted from `Kinship`

Contains the blood kinship algorithm previously inline in `Kinship.calculate/2`:

```elixir
def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
  ancestors_a = Kinship.build_ancestor_map(person_a_id, graph)
  ancestors_b = Kinship.build_ancestor_map(person_b_id, graph)

  # ... MRCA finding (unchanged logic) ...

  person_a = FamilyGraph.fetch_person!(graph, person_a_id)
  mrca = FamilyGraph.fetch_person!(graph, mrca_id)
  relationship = BloodRelationshipLabel.format(steps_a, steps_b, half?, person_a.gender)
  path = build_path(path_a, path_b, steps_a, steps_b, graph)
  # ...
end
```

Every `People.get_person!(id)` → `FamilyGraph.fetch_person!(graph, id)`.

`build_path` and `path_label` move here from `Kinship` (they're blood-specific). `build_path` uses `FamilyGraph.fetch_person!` instead of `People.get_person!`.

### `Kinship.InLaw` — modified to accept graph

DB call replacement map:

| Current call | Replacement |
|---|---|
| `People.get_person!(person_a_id)` (line 27) | `FamilyGraph.fetch_person!(graph, id)` |
| `People.get_person!(person_b_id)` (line 27) | `FamilyGraph.fetch_person!(graph, id)` |
| `Relationships.get_partner_relationship(a, b)` (line 38) | `FamilyGraph.partner_relationship(graph, a, b)` |
| `Relationships.get_all_partners(id)` (lines 98, 121) | `FamilyGraph.all_partners(graph, id)` |
| `Kinship.build_ancestor_map(id)` (lines 99, 102, 124, 125) | `Kinship.build_ancestor_map(id, graph)` |
| `People.get_person!(id)` in `build_in_law_path` (lines 199, 221) | `FamilyGraph.fetch_person!(graph, id)` |
| `Ancestry.Kinship.Label.format/4` in `blood_path_label` (lines 235, 242, 243) | `Ancestry.Kinship.BloodRelationshipLabel.format/4` |

Old arity removed: `calculate/2`.

### `FamilyGraph` additions

Two new lookups on the existing `partners_by_person` index:

```elixir
@doc "Returns [{%Person{}, %Relationship{}}] — all partners (active + former)."
def all_partners(%__MODULE__{} = graph, person_id) do
  Map.get(graph.partners_by_person, person_id, [])
end

@doc "Returns %Relationship{} or nil — partner relationship between two people."
def partner_relationship(%__MODULE__{} = graph, person_a_id, person_b_id) do
  graph.partners_by_person
  |> Map.get(person_a_id, [])
  |> Enum.find_value(fn {p, rel} -> if p.id == person_b_id, do: rel end)
end
```

No new data structures needed.

### `KinshipLive` changes

`maybe_calculate/1` collapses from the 60-line nested case/case (lines 188-248) to:

```elixir
defp maybe_calculate(socket) do
  case {socket.assigns.person_a, socket.assigns.person_b} do
    {%Person{id: a_id}, %Person{id: b_id}} ->
      case Kinship.calculate(a_id, b_id, socket.assigns.family_graph) do
        {:ok, result} ->
          path_a = Enum.slice(result.path, 0, result.steps_a + 1) |> Enum.reverse()
          path_b = Enum.slice(result.path, result.steps_a, length(result.path) - result.steps_a)

          socket
          |> assign(:result, {:ok, result})
          |> assign(:path_a, path_a)
          |> assign(:path_b, path_b)

        error ->
          socket
          |> assign(:result, error)
          |> assign(:path_a, [])
          |> assign(:path_b, [])
      end

    _ ->
      assign(socket, result: nil, path_a: [], path_b: [])
  end
end
```

This works because both `%Kinship{}` and `%InLaw{}` share `.path` and `.steps_a` fields. The template (`kinship_live.html.heex`) distinguishes blood vs in-law by pattern matching on struct type — e.g. `match?({:ok, %Ancestry.Kinship.InLaw{}}, @result)`. These matches continue to work unchanged since the struct module names (`Ancestry.Kinship` and `Ancestry.Kinship.InLaw`) are not being renamed.

Mount unchanged — already builds the graph.

### Label renames

| Before | After | File rename |
|---|---|---|
| `Ancestry.Kinship.Label` | `Ancestry.Kinship.BloodRelationshipLabel` | `label.ex` → `blood_relationship_label.ex` |
| `Ancestry.Kinship.InLawLabel` | `Ancestry.Kinship.InLawRelationshipLabel` | `in_law_label.ex` → `in_law_relationship_label.ex` |

References to update:
- `lib/ancestry/kinship.ex` (alias + calls) → moves to `blood.ex`
- `lib/ancestry/kinship/in_law.ex` (alias + calls)
- `test/ancestry/kinship/label_test.exs` → rename file + module
- `test/ancestry/kinship/in_law_label_test.exs` → rename file + module
- Gettext `.po`/`.pot` files contain developer comments referencing old module names (not `msgid` strings — no runtime impact). Update comments for consistency.
- `lib/ancestry/kinship/in_law.ex` lines 235, 242, 243 — three **unaliased** direct calls to `Ancestry.Kinship.Label.format/4` (not via alias). Must update to `Ancestry.Kinship.BloodRelationshipLabel.format/4`.

## Query budget — before and after

| Scenario | Before | After |
|---|---:|---:|
| Kinship page mount | 2 (graph) | 2 (unchanged) |
| Blood kinship calculate | ~20-50 | 0 |
| In-law calculate (fallback) | ~50-100+ | 0 |
| Select / swap / change persons | ~20-100+ | 0 |

## Semantic change

Both blood and in-law kinship become **family-scoped**, matching the K2 decision in the TreeView N+1 plan. Cross-family ancestor walks and partner hops are excluded. This is consistent with what users can see and select — kinship selectors only offer family members.

## File map

| Action | File |
|---|---|
| Create | `lib/ancestry/kinship/blood.ex` |
| Rename | `lib/ancestry/kinship/label.ex` → `blood_relationship_label.ex` |
| Rename | `lib/ancestry/kinship/in_law_label.ex` → `in_law_relationship_label.ex` |
| Rename | `test/ancestry/kinship/label_test.exs` → `blood_relationship_label_test.exs` |
| Rename | `test/ancestry/kinship/in_law_label_test.exs` → `in_law_relationship_label_test.exs` |
| Modify | `lib/ancestry/kinship.ex` |
| Modify | `lib/ancestry/kinship/in_law.ex` |
| Modify | `lib/ancestry/people/family_graph.ex` |
| Modify | `lib/web/live/kinship_live.ex` |
| Modify | `lib/web/live/kinship_live.html.heex` |
| Modify | `test/ancestry/kinship_test.exs` |
| Modify | `test/ancestry/kinship/in_law_test.exs` |
| Modify | `test/ancestry/people/family_graph_test.exs` |

## Testing

- **Existing blood kinship tests** (`kinship_test.exs`): migrate to `calculate/3` with graph — regression net stays intact
- **Existing in-law tests** (`in_law_test.exs`): migrate to `calculate/3` with graph. Each test setup builds the graph after creating fixtures: `graph = FamilyGraph.for_family(family.id)`. Pass as third arg to all `InLaw.calculate/3` calls. Update describe block names from `"calculate/2"` to `"calculate/3"`.
- **Query-count assertions:** `Blood.calculate/3` and `InLaw.calculate/3` with a pre-built graph must emit **0 DB queries**
- **Family scoping for in-law:** test that a partner-hop through a partner outside the family returns `{:error, :no_relationship}`
- **Label renames:** update module references in test files, verify tests pass
- **FamilyGraph:** add parity tests for `all_partners/2` and `partner_relationship/3`
- **E2E:** existing `test/user_flows/calculating_kinship_test.exs` exercises the full flow

## Risks & mitigations

- **In-law family scoping** — deliberate behavior change (matches blood kinship K2 decision). Mitigation: explicit test that locks in new behavior.
- **Struct pattern matching in templates** — the `render` function must distinguish `%Kinship{}` from `%InLaw{}` for DNA%, partner link rendering. Mitigation: existing template already handles both; the orchestrator just moves the branching from LiveView to `Kinship.calculate/3`.
- **Label rename blast radius** — module renames touch test files and aliases. Mitigation: `mix precommit` catches any missed references at compile time (warnings-as-errors).

## Rollback

Pure code change — no migrations, no data changes. `git revert <commits>` restores previous behavior.

## Success criteria

- `mix precommit` green.
- `Kinship.calculate/3` with a pre-built graph emits **0 DB queries** for both blood and in-law paths.
- All existing kinship + in-law tests pass after migration to `/3`.
- `KinshipLive.maybe_calculate/1` is ≤20 lines (down from ~60).
