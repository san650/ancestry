# Expand Partner Relationships

## Summary

Replace the two partner relationship types (`partner`, `ex_partner`) with four descriptive types (`married`, `relationship`, `divorced`, `separated`), each with its own metadata schema. Update all UI surfaces (person show page, tree view, add/edit modals), the FamilyEcho CSV import, and seeds.

## Approach

**Approach A: Replace type strings directly.** The `type` column values change from `partner`/`ex_partner` to the 4 new types. Each gets its own `PolymorphicEmbed` metadata schema. A helper function `partner_type?/1` groups all 4 as "partner" relationships. No new columns needed.

## Data Model

### New Relationship Types

| New Type | Replaces | Tree/UI Behavior |
|---|---|---|
| `married` | `partner` | Active partner (solid line) |
| `relationship` | `partner` | Active partner (solid line) |
| `divorced` | `ex_partner` | Former partner (dashed line) |
| `separated` | `ex_partner` | Former partner (dashed line) |

### New Metadata Schemas

**`MarriedMetadata`** — `marriage_day`, `marriage_month`, `marriage_year`, `marriage_location`

**`RelationshipMetadata`** — empty embedded schema (no additional fields)

**`DivorcedMetadata`** — `marriage_day`, `marriage_month`, `marriage_year`, `marriage_location`, `divorce_day`, `divorce_month`, `divorce_year`

**`SeparatedMetadata`** — `marriage_day`, `marriage_month`, `marriage_year`, `marriage_location`, `separated_day`, `separated_month`, `separated_year`

> **Rationale**: Separation often follows marriage. Without marriage fields, changing type from `married` to `separated` would silently discard marriage data.

### Helper Functions (on `Relationship` schema)

- `partner_type?(type)` — true for all 4 new types
- `active_partner_type?(type)` — true for `married`, `relationship`
- `former_partner_type?(type)` — true for `divorced`, `separated`

### Symmetric Ordering

`maybe_order_symmetric_ids/1` applies when `partner_type?(type)` is true (replaces the current `type in ~w(partner ex_partner)` check).

### DB Migration

```sql
-- Forward migration
UPDATE relationships
SET type = 'relationship',
    metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"relationship"')
WHERE type = 'partner';

UPDATE relationships
SET type = 'separated',
    metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"separated"')
WHERE type = 'ex_partner';

-- Reverse migration (rollback)
UPDATE relationships
SET type = 'partner',
    metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"partner"')
WHERE type IN ('married', 'relationship');

UPDATE relationships
SET type = 'ex_partner',
    metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{__type__}', '"ex_partner"')
WHERE type IN ('divorced', 'separated');
```

> **Note**: `COALESCE` handles any records with `NULL` metadata to prevent `jsonb_set(NULL, ...)` returning `NULL`.

## Context Layer (`Ancestry.Relationships`)

### Query Functions

Replace the current `get_partners/2` and `get_ex_partners/2` with:

- `get_active_partners(person_id, opts)` — fetches `married` + `relationship` types
- `get_former_partners(person_id, opts)` — fetches `divorced` + `separated` types

Both use the existing `get_relationship_partners/3` helper, modified to accept a list of types and use `r.type in ^types` instead of `r.type == ^type`.

### Replace `convert_to_ex_partner/2`

Remove the delete+recreate transaction. Replace with `update_partner_type(relationship, new_type, metadata_attrs)`:

- In-place update of `type` and `metadata`
- Supports any type transition (e.g. `married` → `divorced`, `relationship` → `separated`, `separated` → `married`)
- Check for unique constraint conflict (same pair already has a relationship of the target type) and return a clear error
- **Metadata carry-over**: When changing types, automatically populate overlapping fields from the current metadata. For example, `married` → `divorced` carries over `marriage_day/month/year/location`. Fields that don't exist in the target schema are discarded. The UI pre-fills the edit modal with carried-over values so the user can review before saving.

### One Partner-Type Relationship Per Pair

A pair of people should only have one partner-type relationship at a time. Add a validation in `create_relationship/4` and `update_partner_type/3` that checks no other partner-type relationship exists between the same pair. This prevents semantically invalid states like Alice and Bob being both `married` and `divorced` simultaneously.

> **DB constraint note**: The existing unique index on `(person_a_id, person_b_id, type)` would still allow multiple partner-type records with different types. Application-level validation is sufficient here — this is a low-concurrency family tree app, not a high-throughput system. The theoretical race condition (two simultaneous requests both passing the check) is acceptable. A partial unique index could be added later if needed.

### Valid Types

Update `@valid_types` to `~w(parent married relationship divorced separated)`.

## Person Show Page

### Partner Section Titles

Each `{partner, rel, children}` group gets a contextual title:

- Active type + partner alive → **"Partner"**
- Active type + partner deceased → **"Late partner"**
- Former type (`divorced`/`separated`) → **"Ex-partner"**

### Replace "Mark as ex-partner" Button

Replace with an "Edit partnership" button that opens the edit relationship modal with a type dropdown at the top. Selecting a type dynamically shows/hides metadata fields. On save, calls `update_partner_type/3` if type changed, or `update_relationship/2` if only metadata changed.

### Unified Edit Relationship Modal

Replace the separate `"partner"` and `"ex_partner"` template branches with a unified partner edit form:

1. Type dropdown: Married, Relationship, Divorced, Separated (pre-selected to current type)
2. Metadata fields rendered dynamically based on selected type:
   - **Married**: marriage date (day/month/year) + location
   - **Relationship**: no fields (note: "No additional details")
   - **Divorced**: marriage date + location + divorce date
   - **Separated**: marriage date + location + separated date (day/month/year)

### Remove Convert-to-Ex Modal

The "Convert to Ex-Partner" modal and its assigns (`converting_to_ex`, `ex_form`) are removed. Functionality absorbed into the edit relationship modal.

### Parents' Relationship Display

The `parents_marriage` lookup in `load_relationships/2` currently only checks `get_partners(p1.id)`. Update to check all partner-type relationships between the two parents (active and former). Display the relationship type label alongside metadata:
- `married` → show "Marriage" + date/location
- `relationship` → show "Relationship" (no metadata)
- `divorced` → show "Divorced" + marriage info + divorce date
- `separated` → show "Separated" + marriage info + separation date

### Metadata Display Helpers

- `format_marriage_info/1` must handle metadata structs that lack marriage fields (e.g. `RelationshipMetadata`). Add a function head that pattern-matches `%RelationshipMetadata{} -> nil` to return early. For other types, use `Map.get/3` with nil defaults for safe access. The template must also guard the `format_marriage_info` call in the parents section — check that `parents_marriage` relationship type is not `"relationship"` before calling it.
- `atomize_metadata/1` integer parsing whitelist must include `separated_day`, `separated_month`, `separated_year` in addition to the existing `marriage_*` and `divorce_*` fields.
- For `relationship` type (empty metadata), display nothing in the metadata area.
- For `separated` type, display marriage info (if present) + "Separated: {date}".

## Add Relationship Component

When `relationship_type == "partner"`, the metadata step shows:

1. A **type dropdown** (Married, Relationship, Divorced, Separated) — default: **"Relationship"**
2. Metadata fields that change dynamically based on selected type (same field sets as the edit modal)

On save, passes the selected type (e.g. `"married"`) to `create_relationship/4` instead of always `"partner"`.

`build_relationship_form/2` initializes with `partner_subtype: "relationship"` as default.

### Form Param Flow

**Add modal**: The type dropdown is a form field named `metadata[partner_subtype]`. In `save_relationship`, extract `partner_subtype` from `params["metadata"]`, pop it from the metadata map, and pass it as the type argument to `create_relationship/4`. The remaining metadata params are the type-specific fields.

**Edit modal**: The type dropdown is a form field named `metadata[partner_subtype]`. In `save_edit_relationship`, compare `params["metadata"]["partner_subtype"]` against `rel.type`. If different, call `update_partner_type/3` with the new type and metadata. If same, call `update_relationship/2` with just the metadata. The `__type__` discriminator is derived from the selected `partner_subtype`, not sent from the form.

Rename the "Add Spouse" button to **"Add Partner"** on the person show page for consistency with the broader relationship types (default is "Relationship", not "Married").

## Tree View (`PersonTree`)

`build_family_unit_full/3` replaces `get_partners` → `get_active_partners` and `get_ex_partners` → `get_former_partners`.

No structural change to tree data — active types feed into partner sorting + previous partners, former types feed into ex-partner groups. The tree template's `data-previous-separator` (solid) and `data-ex-separator` (dashed) still apply correctly.

**Partner sorting fix**: The current sorting at `person_tree.ex:51` accesses `rel.metadata.marriage_year` directly. `RelationshipMetadata` has no `marriage_year` field, so this would crash. Use nil-safe access: `if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil`. Partners without a marriage year sort to the end (lowest priority).

## FamilyEcho Import

- `{:partner, ...}` → `{:relationship, ...}`
- `{:ex_partner, ...}` → `{:separated, ...}`

The CSV orchestrator passes type as `Atom.to_string(type)` to `create_relationship/4`, so this flows through cleanly.

Update the `Adapter` behaviour `@doc` on `parse_relationships/1` to list the new valid type atoms (`:parent`, `:married`, `:relationship`, `:divorced`, `:separated`).

## Seeds

- Relationships with `"partner"` + marriage metadata → `"married"` (semantically correct since they have marriage dates/locations)
- The `"ex_partner"` relationship (William & Linda) → `"divorced"` (has both marriage and divorce metadata)
- Update `__type__` in metadata maps to match new type strings

## File Changes

### Delete
- `lib/ancestry/relationships/metadata/partner_metadata.ex`
- `lib/ancestry/relationships/metadata/ex_partner_metadata.ex`

### Create
- `lib/ancestry/relationships/metadata/married_metadata.ex`
- `lib/ancestry/relationships/metadata/relationship_metadata.ex`
- `lib/ancestry/relationships/metadata/divorced_metadata.ex`
- `lib/ancestry/relationships/metadata/separated_metadata.ex`

### Modify
- `lib/ancestry/relationships/relationship.ex` — new types, helper functions, updated polymorphic embed config
- `lib/ancestry/relationships.ex` — new query functions, remove `convert_to_ex_partner/2`, add `update_partner_type/3`
- `lib/web/live/person_live/show.ex` — remove convert-to-ex assigns/events, update edit_relationship to handle type changes
- `lib/web/live/person_live/show.html.heex` — partner titles, remove convert modal, unified edit modal with type dropdown
- `lib/web/live/shared/add_relationship_component.ex` — type dropdown in partner metadata step
- `lib/ancestry/people/person_tree.ex` — use new query function names
- `lib/web/live/family_live/show.ex` — no structural changes (tree rebuild works unchanged)
- `lib/ancestry/import/csv/family_echo.ex` — update type atoms
- `priv/repo/seeds.exs` — update type strings and metadata `__type__`
- New migration file for DB type/metadata migration

### Tests to Update
- `test/ancestry/relationships_test.exs` — new type strings throughout
- `test/web/live/family_live/tree_multiple_partners_test.exs` — type string updates
- `test/web/live/person_live/relationships_test.exs` — partner/ex-partner flow updates
- `test/web/live/family_live/tree_add_relationship_test.exs` — add relationship from tree
- `test/ancestry/import/csv/family_echo_test.exs` — updated type atoms
- User flow tests exercising partner add/edit/convert workflows
