---
title: "feat: Person-Centered Family Tree View"
type: feat
status: active
date: 2026-03-17
---

# Person-Centered Family Tree View

## Overview

Replace the current full-family graph view (`FamilyGraph` + `Grid` + CSS grid) in `FamilyLive.Show` with a **person-centered tree**. A searchable dropdown at the top selects the "focus person." The tree shows **3 generations of ancestors above** and **3 generations of descendants below** the focus person. Clicking a person's name re-centers the tree; clicking a navigate icon goes to their detail page.

## Problem Statement / Motivation

The current `FamilyGraph` system renders the entire family as a flat graph. This becomes unwieldy with large families (468+ people). Users want to explore the tree relative to a specific person — seeing their direct ancestry and descendants — and navigate by clicking through relatives.

## Proposed Solution

### Data Layer

Create a new `Ancestry.People.PersonTree` module that builds a person-centered tree structure by:

1. Starting from a focus person
2. Traversing **up** via parent relationships for 3 generations
3. Traversing **down** via child relationships for 3 generations
4. At each level, including partner information (couple pairing)

This replaces the complex `FamilyGraph.build/2` → `FamilyGraph.to_grid/1` pipeline with targeted traversal using the existing `Relationships` context functions (`get_parents/1`, `get_children_of_pair/2`, `get_solo_children/1`, `get_partners/1`, `get_ex_partners/1`).

### Layout

Render with HTML/CSS flexbox — each generation is a flex row, centered. Connecting lines drawn with CSS borders (similar to current connectors but simpler). No canvas, no SVG.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Initial focus person | URL query param `?person=:id`; default to first person alphabetically | Supports link sharing, browser history, page refresh |
| URL state management | `push_patch` with `?person=:id` | Re-center is a patch (LiveView stays mounted), navigate icon uses `navigate` |
| Multiple current partners | First partner in center pair; additional treated as ex-partners | Data model allows multiple "partner" rels; UI shows one center pair |
| Ancestor partner display | Show both parents as a couple at each generation (both are direct ancestors) | Natural for genealogy; step-parents (non-ancestors) excluded |
| Descendant partner display | Show partners of descendants at each level (needed for couple cards) | Required for showing couple → children grouping |
| Add placeholder clicks | Navigate to person show page (`/families/:family_id/members/:id`) for now | Existing relationship management UI handles the full workflow |
| Add placeholder scope | Center row (focus person level) + immediate parent slots only | Avoids visual clutter across 7 generations |
| Rendering approach | HTML/CSS flexbox with CSS border connectors | Simple, accessible, no JS dependencies |
| Mobile | Tree area scrollable (overflow-auto), side panel collapses below on mobile | Matches current responsive pattern |
| Deceased indicator | Show year range (e.g., "1920–1985"), subtle opacity reduction | Expected in genealogy apps |
| Deduplication | Allow duplicate appearances; rare edge case, defer handling | Consanguinity is uncommon in the data |
| Focused person highlight | Highlight in side panel people list with distinct background | Visual feedback for current focus |

## Center Row Layout

```
[Ex-Partner A]    [Focus Person + Current Partner]    [Ex-Partner B]
     |                        |                            |
 shared kids            shared kids                   shared kids
                              |
                         solo kids
```

- Focus person appears **once**, paired with current partner (or alone if none)
- Ex-partners appear as separate cards on the same row
- Each couple's children descend independently
- Solo children (no co-parent) descend from focus person

## Ancestor Rows (Above Center)

```
Generation -3:  [GGP1+GGP2]  [GGP3+GGP4]  [GGP5+GGP6]  [GGP7+GGP8]
                    |              |              |              |
Generation -2:    [GP1+GP2]          [GP3+GP4]
                    |                    |
Generation -1:        [Parent1 + Parent2]
                           |
Generation  0:    [Focus Person + Partner]   (center row)
```

- Each person has at most 2 parents → fans out 2x per generation
- Maximum slots: gen-1=2, gen-2=4, gen-3=8
- Empty parent slots show "Add Parent" placeholder

## Descendant Rows (Below Center)

```
Generation  0:   [Focus + Partner]   [Ex-A]   [Ex-B]
                      |                |         |
Generation +1:   [Child1+Spouse] [Child2] [Child3+Spouse] [ExChild1]
                      |                        |
Generation +2:   [GChild1] [GChild2]     [GChild3]
                      |
Generation +3:   [GGChild1]
```

- Each person can have N children → fans out variably
- Children grouped by parent couple
- "Add Child" placeholder shown below focus person's couple(s)

## Person Card Design

Each card shows:
- **Avatar** (photo if processed, gender-colored silhouette placeholder otherwise)
- **Name** (given name + surname, truncated)
- **Life span** (birth_year–death_year, or birth_year–"Living")
- **Gender indicator** — colored top border (blue = male, pink = female, neutral = other)
- **Navigate icon** (small icon in top-right corner) → links to person show page
- **Clickable name/photo** → re-centers tree on that person

Couple cards: two person cards side-by-side in a shared container with a subtle border.

## Placeholder Cards

- **Add Parent**: Circle with `+` icon, "Add Parent" label. Shown at empty parent slots within 3-generation ancestor limit.
- **Add Spouse**: Circle with `+` icon, "Add Spouse" label. Shown next to unpaired focus person.
- **Add Child**: Circle with `+` icon, "Add Child" label. Shown below focus person's couple(s) when no children exist.

All placeholders navigate to the relevant person's show page on click.

## Technical Approach

### Phase 1: Data Layer — `PersonTree` Module

**New file:** `lib/ancestry/people/person_tree.ex`

```elixir
defmodule Ancestry.People.PersonTree do
  @max_depth 3

  defstruct [:focus_person, :ancestors, :center, :descendants]

  # ancestors: list of generation rows (from parents to great-grandparents)
  # Each row: list of %{person_a: person | nil, person_b: person | nil, placeholder_a: bool, placeholder_b: bool}

  # center: %{
  #   focus: person,
  #   partner: person | nil,
  #   ex_partners: [%{person: person, children: [person]}],
  #   solo_children: [person]
  #   partner_children: [person]
  # }

  # descendants: list of generation rows
  # Each row: list of %{person: person, partner: person | nil, children_in_next_gen: [person_id]}

  def build(focus_person_id, family_id) do
    # 1. Load focus person
    # 2. Build center row (partner, ex-partners, children grouping)
    # 3. Traverse ancestors up to @max_depth
    # 4. Traverse descendants up to @max_depth
    # Return %PersonTree{}
  end
end
```

**Key implementation details:**

- Uses existing `Relationships` context functions — no new DB queries needed
- `build_ancestors/3` — recursive: for each person in current gen, call `get_parents/1`, pair them, recurse
- `build_descendants/3` — recursive: for each family unit in current gen, call `get_children_of_pair/2` or `get_solo_children/1`, find their partners, recurse
- Center row uses `get_partners/1`, `get_ex_partners/1`, `get_children_of_pair/2`, `get_solo_children/1`

### Phase 2: Update FamilyLive.Show

**Modified file:** `lib/web/live/family_live/show.ex`

Changes:
- Add `focus_person_id` assign, driven by `handle_params` from URL query param `?person=:id`
- Replace `build_family_graph` + `to_grid` with `PersonTree.build(focus_person_id, family_id)`
- Add `"focus_person"` event handler for click-based re-centering (calls `push_patch`)
- Keep existing: family edit/delete, gallery CRUD, member search/link, PubSub subscription
- Remove: `@graph` and `@grid` assigns

### Phase 3: New Tree Rendering Components

**Modified file:** `lib/web/live/family_live/show.html.heex`

Replace `<.live_component module={CanvasComponent} ...>` with inline tree rendering or a new simpler component.

**Modified file:** `lib/web/live/family_live/person_card_component.ex`

Changes:
- Add navigate icon (hero-arrow-top-right-on-square or similar) in top-right corner
- Name/photo wrapped in a `phx-click="focus_person"` with `phx-value-id={person.id}`
- Navigate icon wrapped in `<.link navigate={...}>`
- Add gender-colored top border
- Support `:placeholder` mode for Add Parent/Spouse/Child cards

**New file:** `lib/web/live/family_live/couple_card_component.ex`

- Container for two person cards side-by-side
- Shared border/background
- Handles: two persons, one person + placeholder, two placeholders

**Simplified connectors:**
- Remove `ConnectorCellComponent` (complex grid-based connectors)
- Remove `UnionConnectorComponent`
- Use simple CSS `::after` / `::before` pseudo-elements on couple cards for vertical lines down to children
- Horizontal lines between sibling groups using CSS borders

### Phase 4: Update Side Panel

**Modified file:** `lib/web/live/family_live/people_list_component.ex`

Changes:
- Split each row into two click targets:
  - Name + avatar: `phx-click="focus_person"` with `phx-value-id={person.id}` → re-centers tree
  - Navigate icon on right: `<.link navigate={~p"/families/#{family_id}/members/#{person.id}"}>`
- Highlight the currently focused person's row (compare `person.id == @focus_person_id`)
- Pass `focus_person_id` assign from parent

### Phase 5: Person Selector Component

**New file:** `lib/web/live/family_live/person_selector_component.ex`

- Searchable dropdown (combo box pattern)
- Lists all family members, filterable by typing
- On select: sends `"focus_person"` event with selected person ID
- Shows current focus person as selected value
- Implementation: text input + dropdown list, filter via `phx-change`, select via `phx-click`
- Uses `phx-click-away` to close dropdown

### Phase 6: Cleanup

**Remove files:**
- `lib/ancestry/people/family_graph.ex`
- `lib/ancestry/people/family_graph/node.ex`
- `lib/ancestry/people/family_graph/union.ex`
- `lib/ancestry/people/family_graph/child_edge.ex`
- `lib/ancestry/people/family_graph/grid.ex`
- `lib/ancestry/people/family_graph/cell.ex`
- `lib/web/live/family_live/canvas_component.ex`
- `lib/web/live/family_live/tree_component.ex`
- `lib/web/live/family_live/union_connector_component.ex`
- `lib/web/live/family_live/connector_cell_component.ex`

**Remove from `lib/ancestry/people.ex`:**
- `build_family_graph/1` function

**Remove from `assets/css/app.css`:**
- `.family-tree-grid` styles

**Keep:**
- `SidePanelComponent` (modified)
- `PeopleListComponent` (modified)
- `GalleryListComponent` (unchanged)
- `PersonCardComponent` (modified)

## System-Wide Impact

- **Routes:** No new routes. Focus person selection uses query params on existing `/families/:family_id` route.
- **Contexts:** No changes to `Relationships` or `People` contexts (new module uses existing functions).
- **PubSub:** No changes needed. Existing family topic subscription handles cover updates. Relationship changes from `PersonLive.Show` currently require page reload — acceptable for now.
- **Tests:** Existing `FamilyGraph` tests can be removed. New tests needed for `PersonTree.build/2`.

## Acceptance Criteria

### Functional

- [ ] Searchable dropdown at top of family page lists all family members
- [ ] Selecting a person from dropdown re-centers tree on that person
- [ ] Tree shows 3 generations of ancestors above focus person
- [ ] Tree shows 3 generations of descendants below focus person
- [ ] Focus person shown in center row with current partner (or alone)
- [ ] Ex-partners shown on sides of center row with their shared children below
- [ ] Solo children shown below focus person
- [ ] Clicking person name/photo on tree card re-centers tree
- [ ] Clicking navigate icon on tree card goes to person show page
- [ ] Clicking person name/photo in side panel re-centers tree
- [ ] Clicking navigate icon in side panel goes to person show page
- [ ] Focus person highlighted in side panel people list
- [ ] "Add Parent" placeholders shown for empty parent slots
- [ ] "Add Spouse" placeholder shown when focus person has no partner
- [ ] "Add Child" placeholder shown when focus person's couple has no children
- [ ] Clicking any placeholder navigates to relevant person's show page
- [ ] URL updates with `?person=:id` when focus changes
- [ ] Page refresh preserves focused person
- [ ] Browser back/forward navigates between focused persons
- [ ] Gender-colored top borders on person cards
- [ ] Deceased persons show year range and subtle visual distinction

### Non-Functional

- [ ] Tree renders in < 200ms for families with 500+ members
- [ ] Layout is responsive — scrollable on mobile, side panel collapses below tree
- [ ] Old `FamilyGraph` code fully removed (no dead code)
- [ ] `mix precommit` passes

## Implementation Order

1. **PersonTree module** (`person_tree.ex`) — pure data, testable in isolation
2. **PersonCardComponent updates** — dual-click, gender border, placeholder mode
3. **CoupleCardComponent** — new component for paired cards
4. **PersonSelectorComponent** — searchable dropdown
5. **FamilyLive.Show rewrite** — swap graph for tree, add focus_person handling
6. **Show template rewrite** — render tree rows from PersonTree data
7. **PeopleListComponent updates** — dual-click, focus highlight
8. **CSS connectors** — simple vertical/horizontal lines between generations
9. **Cleanup** — remove old FamilyGraph files and related code
10. **Tests** — PersonTree unit tests, LiveView integration tests

## Sources & References

- Existing relationship queries: `lib/ancestry/relationships.ex` — `get_parents/1`, `get_children_of_pair/2`, `get_solo_children/1`, `get_partners/1`, `get_ex_partners/1`
- Current person card: `lib/web/live/family_live/person_card_component.ex`
- Person detail page (reference for Add flows): `lib/web/live/person_live/show.ex`
- Current tree layout reference: `lib/ancestry/people/family_graph.ex`
- Design reference: Screenshot of ancestry.com-style person-centered tree (provided by user)
