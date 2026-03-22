# Create Family From Person

Create a new family by selecting a person and automatically linking all their connected relatives (ascendants, descendants, and partners) from the source family.

## Context

People belong to organizations and are linked to families via `FamilyMember` join records. Relationships (parent, married, etc.) are stored globally between person IDs, not scoped to families. The `PersonTree` module already traverses these relationships for rendering, but is capped at 3 generations and designed for display, not extraction.

This feature lets users create a subfamily from a person's connected lineage within an existing family.

## Data & Business Logic

No schema changes are needed. The feature uses existing `Family`, `FamilyMember`, and `Relationship` schemas.

### New function: `Ancestry.Families.create_family_from_person/5`

```elixir
create_family_from_person(organization, family_name, person, source_family_id, opts)
```

- `opts` includes `include_partner_ancestors: boolean` (default `false`)

Inside a `Repo.transaction`:

1. Create a new `Family` with the given name and organization
2. Run a graph traversal to collect all connected person IDs
3. Bulk-insert `FamilyMember` records for each discovered person

### Graph traversal algorithm

BFS starting from the selected person:

- At each visited node, follow:
  - **Parents** (ascendants) — walk upward
  - **Children** (descendants) — walk downward
  - **Partners** (active and former) — always include the partner person
    - If `include_partner_ancestors: true`, also walk up through the partner's parent relationships
- At each step, only include people who are members of `source_family_id` (verified via `FamilyMember` existence)
- Track visited person IDs in a `MapSet` to avoid cycles
- The traversal uses existing `Ancestry.Relationships` query functions (`get_parents/2`, `get_children/2`, `get_active_partners/2`, `get_former_partners/2`), all of which accept a `family_id` option to scope results to family members

The traversal logic lives as private functions within `Ancestry.Families` since it is specific to family creation and not a general-purpose utility.

## UI & Interaction Flow

### Entry point

A new button on the `FamilyLive.Show` toolbar (alongside Edit and Delete). Only visible when the family has people.

### Modal contents

1. **Person selector** — follows the existing `PersonSelectorComponent` pattern (dropdown with search, photo thumbnails). Pre-selects the currently focused person, or the first person if none is focused.
2. **Family name input** — pre-populated with the selected person's `surname` field, or empty if the person has no surname. Updates dynamically when the person selection changes.
3. **Checkbox** — "Include partners' families" (unchecked by default). Helper text: "When checked, ascendants of partners will also be included."
4. **Create button**

### Interaction flow

1. User clicks toolbar button, modal opens with defaults
2. User can change the selected person (name input updates to reflect new person's surname), edit the family name, toggle the checkbox
3. User clicks Create:
   - `create_family_from_person/5` runs inside a transaction
   - On success: `push_navigate` to the new family's show page with `?person={selected_person_id}`
   - On error: flash error on the modal
4. No new routes needed. The modal is handled within `FamilyLive.Show` via assigns, following the same pattern as existing edit/delete/gallery modals.

## Testing

### Context tests

- `create_family_from_person/5` creates a family and links the correct people
- Traversal includes parents, children, and partners of the selected person
- With `include_partner_ancestors: true`, partners' parents are included
- With `include_partner_ancestors: false`, partners' parents are excluded
- People not in the source family are excluded even if they have relationships with included people
- The selected person is always included in the new family
- Edge case: person with no relationships results in a family with only themselves

### User flow test

```
Given a family with several connected people (parents, children, partners)
When the user clicks the "create subfamily" button on the family show page
Then a modal appears with the focused person pre-selected

When the user enters a family name and clicks Create
Then a new family is created with the expected members
And the user is navigated to the new family's show page
And the connected relatives are visible as members
```
