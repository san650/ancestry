# PersonGraph: DCG-to-DAG Conversion

Design spec for updating the family tree graph-to-DAG conversion to handle cycles, duplication, and lateral relatives as documented in `lib/ancestry/people/CLAUDE.md`.

## Summary

The current `PersonTree` module builds a naive recursive tree with no cycle detection — it relies solely on a depth limit to prevent infinite recursion. This design replaces it with `PersonGraph`, which threads a visited map through every recursive call, detects when a person has already been seen, and emits "(duplicated)" stub cards that stop the traversal. The design also covers lateral relatives (siblings, cousins) and user-configurable depth controls.

**Implementation is phased:**
- **Phase 1:** Cycle detection, depth controls, module rename — no laterals
- **Phase 2:** Lateral relative expansion using the `other` depth control

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module name | `PersonGraph` (not `PersonTree`) | It's a DAG with sharing/duplication, not a tree |
| Depth controls | Opts keyword list: `ancestors:`, `descendants:`, `other:` | Single entry point, defaults match spec |
| Visited tracking | Single-pass `%{person_id => generation}` accumulator | Left-side decisions affect right-side — correct per spec |
| Duplicate rendering | Always emit couple node, per-person `duplicated` flag | Couple node anchors connectors and shows partner relationship |
| Shared nodes | No visual sharing — second occurrence is always a "(duplicated)" stub. This is a deliberate divergence from `CLAUDE.md` which describes sharing for same-gen convergence (Type 1). The simpler always-stub approach was chosen during brainstorming; `CLAUDE.md` should be updated to match. | Simpler rendering, consistent behavior, one code path for all cycle types |
| Parent ordering | Deeper parent first, determined by depth probe at focus level only | Richer ancestry rendered fully, shallower side gets stubs |
| Depth probe scope | Focus person's parents only, not recursive at every level | Laterals handle stub optimization at upper levels; diminishing returns |
| Visited set scope | Unified across ancestors, center, and descendants | With laterals, descendant subtrees spawn at multiple ancestor levels — one set flows through everything |
| Build order for laterals | Ancestor couple → expand laterals → add to visited → continue upward | Laterals enter visited before upper traversal, enabling stubs per spec Types 3 and 4 |
| Generation numbering | Focus-relative during construction, renumbered to top-down (top ancestor = 0) before returning | Focus-relative is unambiguous for cycle detection; top-down maps directly to visual rows |

## Data Structures

### PersonGraph struct

```elixir
defstruct [:focus_person, :ancestors, :center, :descendants, :family_id]
```

Unchanged from PersonTree, just renamed.

### Person entries

Every person reference in the tree uses this shape instead of a bare `%Person{}`:

```elixir
%{person: %Person{}, duplicated: boolean()}
```

The renderer checks `duplicated` to show the "(duplicated)" label and suppress ancestry above.

### Ancestor nodes

```elixir
%{
  couple: %{
    person_a: %{person: %Person{}, duplicated: false},
    person_b: %{person: %Person{}, duplicated: true}
  },
  parent_trees: [
    %{tree: <recursive ancestor node>, for_person_id: person_a.id}
    # only entries for non-duplicated persons
  ]
  # Phase 2: laterals: [...]
}
```

Each `parent_trees` entry preserves the existing `%{tree: ..., for_person_id: ...}` shape so the renderer knows which person each ancestry branch belongs to. Only non-duplicated persons get entries. When both persons are duplicated, `parent_trees` is `[]`. The couple node is still emitted (anchors child connectors, shows partner relationship).

### "has more" indicators

At any depth boundary (ancestor, descendant, or lateral), truncated branches show a `has_more: true` flag rather than cutting off silently. This preserves existing `PersonTree` behavior. The renderer shows a visual indicator (e.g., "..." or expand button) on these nodes.

### Visited map

```elixir
# During construction (focus-relative):
%{person_id => generation_level}
# focus = 0, parents = 1, grandparents = 2, children = -1

# After renumbering (top-down):
# top ancestor = 0, focus = max_ancestor_depth, children = max_ancestor_depth + 1
```

## Algorithm

### Entry point

```elixir
def build(focus_person, family_id_or_graph, opts \\ [])
```

Preserves the existing convenience clause that accepts a bare `family_id` integer (builds the graph internally) or a pre-built `%FamilyGraph{}`.

Default opts: `ancestors: 2, descendants: 1, other: 1`.

1. Initialize `visited = %{focus_person.id => 0}`
2. Depth-probe focus person's two parents → sort deeper first
3. Build ancestors upward, threading `visited`
4. Build center family unit (focus person + partners + all descendant groups), threading `visited`. Descendants are built within this step via `build_child_units` — there is no separate descendant pass
5. Renumber: find `max_gen` in visited map, replace all generation values with `max_gen - original`

Steps 3-4 are sequential — ancestors populate `visited` before the center/descendant build sees it.

Note: the `%PersonGraph{}` struct retains a `:descendants` field for future use but it is not populated — descendants live inside `:center` as child groups.

### Depth probe

```elixir
defp max_ancestor_depth(person_id, graph, seen \\ MapSet.new(), depth \\ 0)
```

Lightweight recursion: walks parent edges upward, returns maximum depth. No tree building, no lateral expansion. Uses a simple `MapSet` to guard against cycles in bad data (a person appearing as their own ancestor). Called once to sort focus person's parents.

### Ancestor build

```elixir
defp build_ancestor_tree(person_id, generation, opts, graph, visited)
```

Returns `{ancestor_node | nil, visited}`.

1. Stop if `generation >= opts.ancestors` → return `{nil, visited}`. The caller is responsible for setting `has_more: true` on the last couple node when this returns `nil` but the person has parents in the graph (checked via `FamilyGraph.parents/2 != []`)
2. Look up parents from `FamilyGraph.parents/2`
3. At gen 1 only: sort parents by depth probe result (deeper first)
4. For each parent:
   - In `visited`? → `%{person: parent, duplicated: true}`
   - Not in `visited`? → `%{person: parent, duplicated: false}`, put `parent.id => generation` in visited
5. Build `parent_trees` only for non-duplicated persons, threading `visited` left-to-right (left subtree's visited flows into right subtree)
6. *Phase 2:* If `generation <= opts.other`, expand lateral children → build their descendant subtrees → add to visited
7. Return `{node, visited}`

### Lateral expansion (Phase 2)

After building an ancestor couple at gen N, if `generation <= opts.other`:

1. Get children of the couple using `FamilyGraph.children_of_pair/3` (full siblings of the direct-line child only — half-siblings from other relationships are not included as laterals)
2. Exclude the direct-line child (the one we came from)
3. For each lateral child, add them to `visited` at generation `N - 1` (one below the ancestor couple's generation, i.e., the same absolute row as the direct-line child). Then build their descendant subtree using `build_family_unit_full`, threading `visited`
4. Attach as `laterals: [...]` on the ancestor node

Done before continuing upward, so laterals enter `visited` before the next generation up.

**Lateral descendant depth:** Lateral descendants respect the `descendants` opt measured from the focus person's generation, not from the lateral's own position. A lateral sibling at gen 1 (focus-relative) occupies generation 0 in absolute terms (same row as focus). Their children occupy generation -1 (one below focus). With `descendants: 1`, lateral descendants are shown down to generation -1 from focus — meaning the sibling's children are visible but grandchildren are not. The depth check is: `abs(lateral_child_gen - focus_gen) <= opts.descendants`.

### Center row build

`build_family_unit_full` threads `visited` for all partner groups. Ex-partners and previous partners are checked against the visited set: if an ex-partner's `id` is already in `visited` (e.g., they appeared as a lateral sibling at an ancestor level), they are marked `duplicated: true` in the partner group. Their children are still shown (children are separate people with their own visited checks), but the ex-partner's person card shows the "(duplicated)" label.

### Descendant build

Same as current `build_child_units`, but threads `visited`. If a child's `id` is already in `visited`, emit a stub with `duplicated: true` and don't recurse.

### Parent count invariant

Only the first two parents returned by `FamilyGraph.parents/2` are used. If bad data produces three or more parent relationships for a child, the extras are silently ignored. This preserves existing behavior from the `[{p1, _}, {p2, _} | _]` destructuring pattern.

### Generation renumbering

After the full tree is built:

```elixir
defp renumber(tree, max_gen)
```

Find `max_gen` as the highest positive value in the visited map (ancestors use positive numbers during construction; descendants use negative). Walk every generation annotation in the tree and replace each value with `max_gen - original`.

Example with ancestors: 2, descendants: 1:
- Construction: grandparents = 2, parents = 1, focus = 0, children = -1
- `max_gen` = 2
- Renumbered: grandparents = 0, parents = 1, focus = 2, children = 3

All generation values become non-negative. The top-most ancestor is always generation 0.

## Rendering Changes

### Person card

Receives `%{person: %Person{}, duplicated: boolean()}` instead of bare `%Person{}`.

When `duplicated: true`:
- Show person's name with "(duplicated)" label
- Muted/dimmed styling or dashed border
- Clickable — navigates to re-center the tree on that person
- No "Add Parent" placeholder above

### Ancestor subtree

- Couple node with `parent_trees: []` (both duplicated): render couple card, no connectors above
- One person duplicated: connectors upward only for non-duplicated person's ancestry

### Phase 2: Lateral rendering

New section in ancestor subtree. After rendering the couple card, render lateral children in a horizontal row alongside the direct-line child. Each lateral gets a `family_subtree` for their descendants if any.

## Phase Boundaries

### Phase 1: Cycle detection

Changes:
- Rename `PersonTree` → `PersonGraph` (module, file, all references)
- Add `opts` keyword list with `ancestors:`, `descendants:`, `other:`
- Thread `visited` map through `build_ancestor_tree` and `build_child_units`
- Add `max_ancestor_depth` depth probe
- Change person entries from `%Person{}` to `%{person: %Person{}, duplicated: bool}`
- Add generation renumbering post-processing
- Update renderer to handle `duplicated` flag
- Comprehensive tests

Unchanged:
- `FamilyGraph` — untouched
- `other` opt accepted but defaults to 0 behavior (no laterals)

### Phase 2: Lateral relatives

Changes:
- `other` opt takes effect
- Lateral expansion after each ancestor couple build
- New `laterals` field on ancestor nodes
- New rendering component for lateral children
- Laterals enter `visited` before continuing upward
- Additional tests for lateral-specific cycle resolution

## Test Plan

### Phase 1

#### Cycle types (using seed families from `seeds_test_cycles.exs`)

| Test | Family | Focus | Assertion |
|------|--------|-------|-----------|
| Type 1: cousins marry | Intermarried Clans | Zara | Edgar+Nora reached via Leon and Sylvia — second path marks both as `duplicated: true` |
| Type 2: woman marries two brothers | Intermarried Clans | Phoebe | Gilbert appears as Greta's ex-partner in the couple card (discovered during center build). In Phase 1 (no laterals), Gilbert is NOT duplicated — he's only reached once through the center row. In Phase 2 (with laterals), Gilbert also appears as Humphrey's lateral sibling at the grandparent level — whichever is visited first marks the other as `duplicated: true` |
| Type 3: double first cousins | Intermarried Clans | Quentin | Pemberton GPs and Thornton GPs — second path marks them `duplicated: true` |
| Type 4: uncle marries niece | Intermarried Clans | Felix | Mortimer+Delia at gen 2 via Reginald, gen 3 via Dorinda→Barton — second occurrence stubbed |
| Type 5: siblings marry same family | Intermarried Clans | Noreen | No duplication — partner edges never followed upward |

#### Depth controls

| Test | Assertion |
|------|-----------|
| ancestors: 0 | No ancestor nodes built, just center |
| ancestors: 1 | Only parents shown, grandparents not built |
| ancestors: 3 | Three generations up |
| descendants: 0 | No children shown below focus |
| descendants: 2 | Grandchildren visible |
| Asymmetric depth | Father's side 3 deep, mother's 1 deep — both render correctly, no padding |

#### Deeper-parent-first ordering

| Test | Assertion |
|------|-----------|
| Left parent deeper | Deeper parent is `person_a` in couple, traversed first |
| Equal depth | Stable order — falls back to `FamilyGraph.parents/2` return order (insertion-dependent; non-deterministic across re-seeds but stable within a session) |
| One parent unknown | Single parent, no sorting needed |

#### Visited map threading

| Test | Assertion |
|------|-----------|
| Focus person in visited | `visited` starts with focus person at gen 0 |
| Ancestor added to visited | Each non-duplicated ancestor in visited with correct generation |
| Duplicated ancestor not traversed | `parent_trees` empty for duplicated persons |
| Both parents duplicated | Couple node emitted with `parent_trees: []` |
| Descendant in visited (Phase 2) | Child already seen as lateral — stubbed in descendants |

#### Generation renumbering

| Test | Assertion |
|------|-----------|
| Simple 2-gen tree | Focus = 2, parents = 1, grandparents = 0 |
| Asymmetric branches | Max depth drives renumbering, shallower side correct |
| With descendants | Descendants get numbers > focus generation |

#### No-cycle families

| Test | Family | Focus | Assertion |
|------|--------|-------|-----------|
| Simple lineage | Blended Saga | Victor | No person marked duplicated despite multiple ex-partners |
| Deep lineage | Prolific Elders | Montague | No duplication, all ancestors unique |
| Single parent | (inline) | — | Couple card with one person, single branch above |
| No parents known | (inline) | — | `ancestors: nil`, center still built |
| No children | (inline) | — | Center has empty child groups |

#### Partner grouping (preserved behavior)

| Test | Assertion |
|------|-----------|
| Multiple active partners | Sorted by marriage year DESC, latest is main partner |
| Ex-partners | Grouped separately with their children |
| Solo children | No co-parent, separate group |
| No partners | `partner: nil`, empty groups |

#### Edge cases

| Test | Assertion |
|------|-----------|
| Person is their own ancestor (bad data) | Visited catches at gen 0 — upward path stubs immediately |
| Same person as both parents (bad data) | Second parent entry marked `duplicated: true` |
| Three parents (bad data) | Only first two used |
| Empty family graph | Returns PersonGraph with nil ancestors, minimal center |
| Depth probe with cycle (bad data) | Probe terminates via `seen` MapSet, doesn't stack overflow |

### Phase 2

| Test | Assertion |
|------|-----------|
| Other: 0 | No lateral children at any ancestor level |
| Other: 1 | Siblings of focus visible at gen 1, no cousins |
| Other: 2 | Siblings at gen 1, aunts/uncles at gen 2 with their children |
| Lateral enters visited | Sibling visible → same person on other path stubbed |
| Type 3 with laterals | Brother-Y and Sister-Y stubbed as laterals, GPs not duplicated |
| Type 4 with laterals | Brother stubbed as lateral, grandparents not duplicated |
| Prolific Elders Other: 1 | All 12 siblings of Montague visible with families |
| Lateral descendant depth | Respects `descendants` opt from focus person's perspective |
| Lateral has no descendants | Shown as leaf card, no subtree |
| ancestors: 2, other: 1 interaction | Laterals at gen 1 (siblings) expanded; their descendants respect `descendants` opt from focus perspective |
| Ex-partner as lateral | Ex-partner discovered in center row AND as lateral sibling — second occurrence marked `duplicated: true` |
| has_more on depth boundary | Truncated branches at ancestor/descendant/lateral limits show `has_more: true` |
