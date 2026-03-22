# Create Family From Person

Create a new family by selecting a person and automatically linking all their connected relatives (ascendants, descendants, and partners) from the source family.

## Context

People belong to organizations and are linked to families via `FamilyMember` join records. Relationships (parent, married, etc.) are stored globally between person IDs, not scoped to families. The `PersonTree` module already traverses these relationships for rendering, but is capped at 3 generations and designed for display, not extraction.

This feature lets users create a subfamily from a person's connected lineage within an existing family.

## Data & Business Logic

No schema changes are needed. The feature uses existing `Family`, `FamilyMember`, and `Relationship` schemas.

### New function: `Ancestry.Families.create_family_from_person/5`

```elixir
create_family_from_person(%Organization{} = organization, family_name, %Person{} = person, source_family_id, opts)
```

- Accepts `%Organization{}` struct (matching `Families.create_family/2` pattern) and `%Person{}` struct (extracts `.id` internally)
- `opts` includes `include_partner_ancestors: boolean` (default `false`)

Inside a `Repo.transaction`:

1. Create a new `Family` with the given name and organization
2. Run a graph traversal to collect all connected person IDs
3. Bulk-insert `FamilyMember` records using `Repo.insert_all` (safe because the family is new, so no duplicate `[:family_id, :person_id]` conflicts, and all people already belong to the same organization via source family membership)
4. Set the selected person as the default member of the new family

### Graph traversal algorithm

BFS starting from the selected person with **no depth limit** (unlike `PersonTree` which caps at 3 generations):

- At each visited node, follow:
  - **Parents** (ascendants) — walk upward recursively
  - **Children** (descendants) — walk downward recursively. This includes all children of visited nodes, even if the node was reached via a partner edge (true connected-component behavior). For example, if Person A is married to Person B who has children with Person C from a prior relationship, those children are included if they are source family members.
  - **Partners** (active and former) — always include the partner person
    - If `include_partner_ancestors: true`, also walk up through the partner's parent relationships
    - If `include_partner_ancestors: false`, the partner is included but their parents are not traversed
- At each step, only include people who are members of `source_family_id` — this is handled by passing the `family_id` option to the existing `Ancestry.Relationships` query functions (`get_parents/2`, `get_children/2`, `get_active_partners/2`, `get_former_partners/2`)
- Track visited person IDs in a `MapSet` to avoid cycles and redundant queries

**Note on return types:** The relationship query functions return different shapes — `get_children/2` returns `[%Person{}]` while the others return `[{%Person{}, %Relationship{}}]`. The BFS must extract person IDs appropriately from each.

The traversal logic lives as private functions within `Ancestry.Families` since it is specific to family creation and not a general-purpose utility.

## UI & Interaction Flow

### Entry point

A "Create subfamily" button on the `FamilyLive.Show` toolbar (alongside Edit and Delete). Only visible when `@people != []`.

### Modal contents

1. **Person selector** — reuses `PersonSelectorComponent`, parameterized with a configurable event message name (e.g., `on_select_msg`) so it updates the modal state instead of triggering page navigation. Pre-selects the currently focused person, or the first person in `@people` (ordered by surname, given_name) if none is focused.
2. **Family name input** — pre-populated with the selected person's `surname` field, or empty if nil. Updates dynamically when the person selection changes. Validated via `phx-change` with inline error display (matching existing edit family modal pattern). Required, 1-255 characters.
3. **Checkbox** — "Include partners' families" (unchecked by default). Helper text: "When checked, ascendants of partners will also be included."
4. **Create button** — with `phx-disable-with="Creating..."` to prevent double-clicks and show loading state during traversal.

### Modal behavior

- Dismissible via Escape key and backdrop click (matching existing modal patterns)
- `phx-change` event for real-time name validation
- Duplicate family names are allowed (no unique constraint on family names)

### Interaction flow

1. User clicks "Create subfamily" button → modal opens with defaults
2. User can change the selected person (name input updates to reflect new person's surname), edit the family name, toggle the checkbox
3. User clicks Create:
   - `create_family_from_person/5` runs inside a transaction
   - On success: `push_navigate` to the new family's show page with `?person={selected_person_id}`
   - On error: changeset errors display inline for validation failures; generic flash error for unexpected failures
4. No new routes needed. The modal is handled within `FamilyLive.Show` via assigns, following the same pattern as existing edit/delete/gallery modals.

## Testing

### Context tests

- `create_family_from_person/5` creates a family and links the correct people
- Traversal includes parents, children, and partners of the selected person
- With `include_partner_ancestors: true`, partners' parents are included
- With `include_partner_ancestors: false`, partners' parents are excluded
- People not in the source family are excluded even if they have relationships with included people
- The selected person is always included in the new family
- The selected person is set as the default member of the new family
- Edge case: person with no relationships results in a family with only themselves
- Partner's children from other relationships are included if they are source family members
- Transaction rolls back entirely if any step fails (no partial family creation)
- Person already in multiple families can be added to the new family too

### User flow test

```
Given a family with several connected people (parents, children, partners)
When the user clicks the "Create subfamily" button on the family show page
Then a modal appears with the focused person pre-selected

When the user changes the selected person
Then the family name input updates to the new person's surname

When the user enters a family name and clicks Create
Then a new family is created with the expected members
And the user is navigated to the new family's show page
And the connected relatives are visible as members

Given the modal is open
When the user clears the family name and clicks Create
Then a validation error is shown on the name field

Given the modal is open
When the user presses Escape
Then the modal closes without creating a family
```
