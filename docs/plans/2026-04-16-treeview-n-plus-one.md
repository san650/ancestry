# Fix FamilyTree N+1 Queries

**Date:** 2026-04-16
**Status:** Design approved — awaiting implementation plan
**Branch:** `treeview-n-plus-one`

## Problem

A single `GET /org/1/families/9?person=348` (one TreeView load for one family) emits **234 database queries** per LiveView mount, and LiveView mounts twice (disconnected + connected), so a full page load is **~468 queries**. Every refocus click (`push_patch` with a different `?person=` param) re-emits another ~234. Today's DB time is fast (~0.3 ms/query, 68 ms total), but the cost is **sequential round-trips** — on production with any network latency this scales very poorly. The same pattern exists in `Ancestry.Kinship`, which runs interactively on every selector change in `KinshipLive`.

Both issues share a root cause: recursive in-Elixir traversal that calls a `Repo` query per visited person.

## Goal

Take the family TreeView from **468 queries per page load to 4**, and **refocus clicks from 234 to 0**. Take kinship from **~100+ queries per `calculate` to 0** after a 2-query graph load. Preserve all current behavior.

## Root-cause diagnosis (from `request.log`)

91% of queries for one TreeView load are from `Ancestry.People.PersonTree`. Call-site counts for one mount:

| Call site | Count | Pattern |
|---|---:|---|
| `Relationships.get_relationship_partners/3:211` | 148 | 4 per person visited: active×(as_a + as_b) + former×(as_a + as_b) |
| `PersonTree.build_family_unit_full/3:97` (`get_solo_children`) | 36 | 1 per family unit |
| `PersonTree.build_ancestor_tree/3:144` (`get_parents`) | 14 | 1 per ancestor |
| `PersonTree.build_family_unit_full/3:69` (`get_children_of_pair`, main partner) | 10 | 1 per couple |
| `PersonTree.build_family_unit_full/3:89` (`get_children_of_pair`, ex-partner) | 4 | 1 per ex-partner |
| `PersonTree.build_child_units/4:116` (at-depth-limit `get_children` + `get_active_partners`) | 2 | 1 per at-limit child |

`Kinship` adds per-`calculate` two more fan-outs:

- `Kinship.bfs_expand/3:108` calls `Relationships.get_parents(id)` once per person visited in the BFS, for both A and B, up to `@max_depth = 10`.
- `Kinship.build_path/4:276` calls `People.get_person!(id)` once per node in the A→MRCA→B path.

The family is already the right scoping unit. `Ancestry.Relationships.list_relationships_for_family/1` already exists and returns the entire relationship graph for a family in **one query**. `mount` already loads all persons for the family in **one query**. With both in memory, all the recursive traversal can run without touching the DB.

## Architecture

### New module: `Ancestry.People.FamilyGraph`

Lives at `lib/ancestry/people/family_graph.ex`. Single responsibility: own the in-memory indexes of a family's person/relationship graph and expose the exact read API that `PersonTree` and `Kinship` reach for today.

**Struct:**

```elixir
%FamilyGraph{
  family_id: integer(),
  people_by_id: %{integer() => %Person{}},
  # parents pointing TO a given child. Built ONLY from relationships where
  # type == "parent" (not from partner rows).
  parents_by_child: %{integer() => [{%Person{}, %Relationship{}}]},
  # children of a given parent (person_a_id on type == "parent" rows),
  # pre-sorted by birth_year ASC NULLS LAST, id ASC — matches today's DB ordering.
  # Use a sort key like `{is_nil(p.birth_year), p.birth_year, p.id}` so nils sort last.
  children_by_parent: %{integer() => [%Person{}]},
  # partners keyed by EITHER endpoint. The relationships table enforces
  # person_a_id < person_b_id, so a row {a, b} is stored once. The index
  # must populate BOTH directions: entries under a pointing to b and under
  # b pointing to a. This replicates today's `as_a ++ as_b` union in
  # Relationships.get_relationship_partners/3.
  partners_by_person: %{integer() => [{%Person{}, %Relationship{}}]}
}
```

**Constructors:**

- `FamilyGraph.for_family(family_id) :: %FamilyGraph{}` — runs exactly **two queries**: `People.list_people_for_family/1` + `Relationships.list_relationships_for_family/1`, then folds them into the four maps.
- `FamilyGraph.from(people, relationships, family_id) :: %FamilyGraph{}` — same construction from pre-loaded lists, so `FamilyLive.Show.mount/3` can build the graph using its existing `:people` assign plus one extra relationships query, avoiding a duplicate persons fetch.

**Family scoping correctness:** `list_relationships_for_family/1` keeps only relationships where both endpoints are family members. This matches today's `maybe_filter_by_family` semantics in `Ancestry.Relationships` — relationships crossing the family boundary stay hidden, exactly as now.

### Lookup API — mirrors the subset of `Ancestry.Relationships` that `PersonTree` and `Kinship` use

| Function | Returns | Replaces today's |
|---|---|---|
| `active_partners(graph, person_id)` | `[{%Person{}, %Relationship{}}]` | `Relationships.get_active_partners(id, family_id: …)` |
| `former_partners(graph, person_id)` | `[{%Person{}, %Relationship{}}]` | `Relationships.get_former_partners(id, family_id: …)` |
| `parents(graph, person_id)` | `[{%Person{}, %Relationship{}}]` | `Relationships.get_parents(id, family_id: …)` |
| `children(graph, person_id)` | `[%Person{}]` | `Relationships.get_children(id, family_id: …)` |
| `children_of_pair(graph, a_id, b_id)` | `[%Person{}]` | `Relationships.get_children_of_pair(a, b, family_id: …)` |
| `solo_children(graph, person_id)` | `[%Person{}]` | `Relationships.get_solo_children(id, family_id: …)` |
| `has_children?(graph, person_id)` | `boolean()` | `Relationships.get_children(id, opts) != []` at depth limit |
| `fetch_person(graph, person_id)` | `%Person{}` or raises | `People.get_person!(id)` (used by `Kinship.build_path`) |

**Return-type parity:** tuples `{person, rel}` for partner/parent functions match existing pattern matches in `PersonTree` (`[{p, _rel} | rest]`, `Map.get(rel.metadata, :marriage_year)`, …). Plain `[person]` for children functions. No downstream shape changes.

**Sort semantics — preserved from DB:**

- `children`, `children_of_pair`, `solo_children`: `birth_year ASC NULLS LAST`, then `id ASC`. Sorted once at graph construction.
- `parents`, `active_partners`, `former_partners`: no DB ordering today — preserved as insertion order. `PersonTree`'s own in-memory sort (by `marriage_year` descending for "latest partner is main") continues to apply on top.

**Non-trivial semantic translations:**

- `solo_children(X)` — for each `child_id` in `children_by_parent[X]`, keep it iff `parents_by_child[child_id]` has exactly one entry. Requires `parents_by_child` to be type-filtered to `"parent"` (see struct doc above). Matches the SQL `LEFT OUTER JOIN … WHERE r2.id IS NULL` exactly.
- `children_of_pair(A, B)` — for each `child_id` in `children_by_parent[A]`, keep it iff `B` also appears as a parent in `parents_by_child[child_id]` (i.e. `B` is one of the `person_a_id`s on the child's parent-type relationships). Matches the SQL double `INNER JOIN` exactly.

**Intentionally NOT mirrored:** `get_children_with_coparents`, `get_siblings`, `get_partner_relationship`, `list_relationships_for_person` — not called by `PersonTree` or `Kinship`. Stay in `Ancestry.Relationships`. No scope creep.

### `PersonTree` changes

**Public API — two arities resolving to one internal builder:**

```elixir
# Legacy-compatible: builds the graph itself, then walks it.
PersonTree.build(%Person{} = focus_person, family_id) :: %PersonTree{}

# Graph-aware: caller supplies a pre-built graph. Fast path used by LiveView.
PersonTree.build(%Person{} = focus_person, %FamilyGraph{} = graph) :: %PersonTree{}
```

Pattern-match on the second arg. The 5 existing `FamilyLive.Show` call sites keep working unchanged during migration.

**Nil-`family_id` handling during migration:** until commit 6 removes the no-family arity, `build(focus, nil)` must still work (one test at `person_tree_test.exs:50` relies on it). Commit 2 preserves this: the `is_integer(family_id)` clause shown below is augmented by a `nil`-matching clause that walks the full org (simplest implementation: pre-load via `FamilyGraph.for_family/1` using `focus_person`'s `organization_id` — or keep the old DB-walking path for that one arity until commit 6 deletes it). Alternatively, reorder so commit 6 lands before commit 2. Whichever the implementer chooses must keep every commit individually green.

**Internal threading — replace `opts` with `graph`:**

Every private helper (`build_center`, `build_family_unit_full`, `build_child_units`, `build_ancestor_tree`) drops its `opts` keyword list in favor of `graph` as the last argument. Every `Relationships.get_X(person.id, opts)` becomes `FamilyGraph.X(graph, person.id)`. The rest of each helper — partner sorting by marriage year, `at_limit` branching, previous-vs-ex-partner grouping, `has_more` computation — stays byte-identical.

Sketch:

```elixir
def build(%Person{} = focus_person, family_id) when is_integer(family_id) do
  build(focus_person, FamilyGraph.for_family(family_id))
end

def build(%Person{} = focus_person, %FamilyGraph{} = graph) do
  %__MODULE__{
    focus_person: focus_person,
    ancestors: build_ancestor_tree(focus_person.id, 0, graph),
    center: build_family_unit_full(focus_person, 0, graph),
    family_id: graph.family_id
  }
end
```

**Graph lifetime:** consumed during `build` and discarded. Does not appear in the returned `%PersonTree{}`. Rendering code, streams, and socket state are untouched.

**No-family-scope arity dropped:** `PersonTree.build/1` (today's `family_id \\ nil` default) has no production callers — only one test at `test/ancestry/people/person_tree_test.exs:50`. Arity is removed; that test is updated to pass a `family_id` or deleted if it's testing a dead path.

### `FamilyLive.Show` integration

Add a `:family_graph` socket assign. Built once per mount, reused by every event that rebuilds the tree.

**Mount** already loads `:people`. Add one call:

```elixir
people = People.list_people_for_family(family_id)
relationships = Relationships.list_relationships_for_family(family_id)
family_graph = FamilyGraph.from(people, relationships, family_id)
|> assign(:people, people)
|> assign(:family_graph, family_graph)
```

**The 5 `PersonTree.build` call sites — what each does today and what changes:**

| Line | Handler | Today | After |
|---:|---|---|---|
| 93 | `handle_params` | Rebuild tree on every param change. Graph unchanged. | `PersonTree.build(focus_person, socket.assigns.family_graph)`. **0 queries.** |
| 174 | `handle_event("save", …)` (family edit) | Rebuilds tree after family-name/cover save. People/relationships are unchanged, BUT the save handler can change the family's default person, which changes `focus_person`. | Reuse cached `:family_graph` (no DB); rebuild tree in memory only if `focus_person` changed. **0 queries.** Do not drop the rebuild entirely — it would regress the default-person feature from `docs/plans/2026-03-19-default-person.md`. |
| 356 | `handle_event("link_person", …)` | Adds an existing person to the family. People + relationships can change. | Call `refresh_graph_and_tree/1` helper: reload people, reload relationships, rebuild graph + tree. **2 queries.** |
| 420 | `handle_event("import_csv", …)` | Bulk CSV import. People + relationships change. | Call `refresh_graph_and_tree/1`. **2 queries.** |
| 580 | `handle_info({:relationship_saved, …})` | Relationship created/edited via shared component. Can also create a new person. | Call `refresh_graph_and_tree/1`. **2 queries.** |

Helper:

```elixir
defp refresh_graph_and_tree(socket) do
  family_id = socket.assigns.family.id
  people = People.list_people_for_family(family_id)
  relationships = Relationships.list_relationships_for_family(family_id)
  graph = FamilyGraph.from(people, relationships, family_id)
  tree =
    case socket.assigns.focus_person do
      nil -> nil
      focus -> PersonTree.build(focus, graph)
    end
  assign(socket, people: people, family_graph: graph, tree: tree)
end
```

### `Kinship` + `KinshipLive` changes (K2 — family-scoped)

`Kinship.calculate/2` today walks ancestors with no family filter, but `KinshipLive`'s selectors only offer persons from the current family. Aligning kinship to the family scope matches what the user can actually see and select. Cross-family ancestor walks are lost; this is considered an acceptable and arguably more correct behavior. If a future feature needs org-wide kinship, it can be added as a separate `FamilyGraph.for_org/1` without disturbing this refactor.

**`Ancestry.Kinship` changes:**

- New primary arity: `Kinship.calculate(person_a_id, person_b_id, %FamilyGraph{} = graph)`.
- `bfs_expand/3` calls `FamilyGraph.parents(graph, id)` instead of `Relationships.get_parents(id)`.
- `build_path/4` reads persons from `graph.people_by_id` via `FamilyGraph.fetch_person/2` instead of `People.get_person!/1`.
- MRCA person is pulled from `graph.people_by_id`, no DB.
- Old `calculate/2` arity is removed. All call sites (the single `KinshipLive` caller + all tests) are updated.

**`Web.KinshipLive` changes:**

- `mount/3` builds `:family_graph` the same way `FamilyLive.Show` does (one extra relationships query on top of the existing people load).
- `maybe_calculate/1` calls `Kinship.calculate(a_id, b_id, socket.assigns.family_graph)`. Every selector change, swap, and param-driven recalculation becomes **0 queries**.
- If `family_id` changes (it can't within a single mount — route is family-scoped), no invalidation logic is needed.

### Orthogonal cleanup

One-line fix in `Ancestry.Relationships.get_relationship_partners/3`: replace `Repo.all(as_a) ++ Repo.all(as_b)` with a single query using `person_a_id = ? OR person_b_id = ?`. `PersonTree` and `Kinship` stop calling this path after the refactor, but any future caller (or `Kinship`'s removed arity while still deprecated) still benefits. Self-contained ~5-line change.

## Query budget — before and after

| Scenario | Before | After |
|---|---:|---:|
| Family page full load (disconnected + connected mount) | ~468 | 4 |
| Refocus click (`push_patch` with new `?person=`) | ~234 | 0 |
| Add relationship / link person / CSV import | ~234 | 2 |
| Family name/cover edit (save; possibly changes default person → rebuild tree from cached graph) | ~234 | 0 |
| Kinship page load (mount + `?person_a=`, `?person_b=`) | ~100+ (variable) | 2 |
| Kinship: select / swap / change persons | ~100+ | 0 |

## Testing

### New: `test/ancestry/people/family_graph_test.exs`

- **Graph-construction budget:** attach a Telemetry handler to `[:ancestry, :repo, :query]`, call `FamilyGraph.for_family(family.id)`, assert exactly **2 queries emitted**. This is the load-bearing guarantee; it needs a regression test.
- **Per-function SQL parity suite:** for each of `active_partners`, `former_partners`, `parents`, `children`, `children_of_pair`, `solo_children`, `has_children?`, iterate over fixture people and assert `FamilyGraph.X(graph, id)` returns the same result (after sorting where sort is defined) as the equivalent `Relationships.X(id, family_id: family.id)` call. Catches any drift in the non-trivial translations (`solo_children`, `children_of_pair`).
- **Family scoping:** a fixture relationship whose other endpoint is outside the family is absent from every lookup.
- **Edge cases:** person with 0 / 1 / 2 parents; couple with no children; ex-partner with children; a child that appears under multiple parent-pairs.

### Updated: `test/ancestry/people/person_tree_test.exs`

- All existing DB-backed tests keep passing unchanged — they call `PersonTree.build(person, family_id)`, which now routes through `FamilyGraph` internally. This is the regression net.
- Add one new test that constructs a `%FamilyGraph{}` (either via `for_family/1` or manually from fixtures) and passes it to `PersonTree.build(focus, graph)`, verifying the new arity.
- Delete or update the one `PersonTree.build(person)` call (no-family arity) at line 50.

### Updated: `test/ancestry/kinship_test.exs`

- All 25+ existing tests migrate to build a `%FamilyGraph{}` from their fixture data and call `Kinship.calculate(a_id, b_id, graph)`. This pins the new contract in the pre-existing coverage.
- Add a query-count assertion: `Kinship.calculate/3` with a pre-built graph must emit **0 DB queries**.
- Semantic-change coverage: add a test that two family members sharing an ancestor **outside** the family now return `{:error, :no_common_ancestor}` — locks in the deliberate behavior change from K2.

### E2E (`test/user_flows/`)

Per `CLAUDE.md`, every changed user flow needs E2E coverage. Audit the existing flows for:

- Family view — load, refocus, add relationship, link person, CSV import, family edit.
- Kinship — load with prefilled params, select, swap, clear.

Add missing flows. Add a **query-count assertion** at the HTTP boundary for the family-view flow (load `/org/:org_id/families/:family_id?person=:id` and assert total query count ≤ 12 — leaves margin for auth, org, family, persons, relationships, galleries, vaults, default person, metrics) and for the kinship flow (mount + calculate ≤ 5).

## Rollout — one PR, six commits

Each commit is independently green, reviewable, and revertable. `mix precommit` after each.

1. **Add `FamilyGraph` module + tests.** Pure addition, no callers. All tests green.
2. **Add `PersonTree.build(focus, %FamilyGraph{})` arity; route `build(focus, family_id)` through it.** `PersonTree` internal helpers take `graph` instead of `opts`. Existing `PersonTree` tests stay green and now exercise the new path.
3. **Update `FamilyLive.Show`:** `:family_graph` assign in `mount`, `refresh_graph_and_tree/1` helper, rewire all 5 call sites. Line 174 (family save) reuses the cached graph and rebuilds the tree only if the default-person change moved `focus_person`. Verify E2E flows.
4. **Migrate `Kinship` + `KinshipLive` to `FamilyGraph`.** New `Kinship.calculate/3`; `KinshipLive` builds graph in `mount`; all callers and tests updated; old `calculate/2` arity removed.
5. **Collapse `Relationships.get_relationship_partners/3`** into a single `person_a_id = ? OR person_b_id = ?` query. Orthogonal cleanup.
6. **Remove `PersonTree.build/1`** (no-`family_id` arity) and update/delete the one stale test.

PR description links this spec and includes before/after query counts captured via Tidewave `get_logs` for the URL `/org/1/families/9?person=348`.

## Risks & mitigations

- **Semantic drift between SQL and in-memory lookups** — highest risk, concentrated in `solo_children` and `children_of_pair`. Mitigation: per-function SQL-parity test suite in `FamilyGraph` tests, exercised against fixture data.
- **Kinship behavior change (cross-family → family-scoped)** — deliberate. Mitigation: explicit test that covers the new behavior so it's locked in and visible in future reviews. Called out in the PR description.
- **Stale graph within a long-lived LiveView session** — if a concurrent user in another session edits relationships, the current session keeps a stale graph until its next refresh point. This is already the behavior today; out of scope.
- **Large families** — the graph is O(persons + relationships). At thousands of rows per family, still tens of KB in process memory. No concern at expected scale; correct behavior for any size.
- **Silent breakage** — mitigated by the existing `PersonTree` / `Kinship` suites (which stay green throughout migration) plus the query-count assertions at the HTTP boundary.

## Rollback

Pure code change — no migrations, no data changes. `git revert <commits>` restores previous behavior without coordination.

## Success criteria

- `mix precommit` green.
- All existing + new tests green, including the `FamilyGraph` parity suite.
- `GET /org/:org_id/families/:family_id?person=:person_id` emits ≤ 4 `PersonTree`-or-`FamilyGraph`-related queries across the full disconnected + connected mount lifecycle, verified via a fresh `request.log` / Tidewave `get_logs`.
- A refocus click issues **0** new queries from `PersonTree` or `FamilyGraph`.
- `Kinship.calculate/3` with a pre-built graph issues **0** DB queries, verified by unit test.

## Out of scope

- `Ancestry.Families.Metrics` query fan-out (5 queries per mount) — separate concern, independently addressable later.
- `memory_vaults` / `galleries` queries — already single-shot, no issue.
- Cross-session graph invalidation — current app has no mechanism and no observed complaint.
- Org-wide kinship — if ever needed, add `FamilyGraph.for_org/1` as a separate feature.
