# Family-Scoped Tree View Design

## Problem

When a person belongs to multiple families and is selected in a family's TreeView, the tree displays people from ALL families instead of only people belonging to the current family. This is because `PersonTree` builds the tree using global relationship queries (`Relationships.get_parents/1`, `get_children/1`, etc.) that don't filter by family membership.

## Solution

Add an optional `family_id` parameter to relationship query functions. When provided, queries join on `family_members` to ensure returned people belong to that family. When omitted, behavior is unchanged (preserving Kinship's global traversal).

## Changes

### Relationships Context (`lib/ancestry/relationships.ex`)

Add optional `opts \\ []` parameter to:
- `get_parents/2`
- `get_children/2`
- `get_children_of_pair/3`
- `get_solo_children/2`
- `get_partners/2`
- `get_ex_partners/2`

When `opts[:family_id]` is present, join on `family_members` to filter returned people by family membership. When absent, queries work globally as they do today.

### PersonTree (`lib/ancestry/people/person_tree.ex`)

- Add `family_id` field to the `PersonTree` struct
- Accept `family_id` in `build/2` -> `build(person, family_id)`
- Thread `family_id` through all recursive calls (`build_ancestors`, `build_family_unit_full`, etc.)
- Pass `family_id: family_id` as opts to every `Relationships.get_*` call

### FamilyLive.Show (`lib/web/live/family_live/show.ex`)

- Pass `family.id` when building the `PersonTree`

### No Changes Required

- **Kinship** (`lib/ancestry/kinship.ex`) — continues calling `get_parents/1` and `get_children/1` without `family_id`, traversing globally as intended
- **Search/link people** — `search_people/2` already searches outside the family (for linking), `search_family_members/3` already searches within the family (for relationships)
- **PersonSelectorComponent** — already filters from family-scoped `@people` assign
- **AddRelationshipComponent** — already uses `search_family_members/3`

## Testing

- Add a test with a person shared across two families
- Build PersonTree with family_id and verify only family members appear
- Verify Kinship still works globally without family_id
