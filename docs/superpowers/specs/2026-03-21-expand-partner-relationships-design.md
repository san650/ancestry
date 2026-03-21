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

**`SeparatedMetadata`** — `separated_day`, `separated_month`, `separated_year`

### Helper Functions (on `Relationship` schema)

- `partner_type?(type)` — true for all 4 new types
- `active_partner_type?(type)` — true for `married`, `relationship`
- `former_partner_type?(type)` — true for `divorced`, `separated`

### Symmetric Ordering

`maybe_order_symmetric_ids/1` applies when `partner_type?(type)` is true (replaces the current `type in ~w(partner ex_partner)` check).

### DB Migration

```sql
UPDATE relationships
SET type = 'relationship',
    metadata = jsonb_set(metadata, '{__type__}', '"relationship"')
WHERE type = 'partner';

UPDATE relationships
SET type = 'separated',
    metadata = jsonb_set(metadata, '{__type__}', '"separated"')
WHERE type = 'ex_partner';
```

## Context Layer (`Ancestry.Relationships`)

### Query Functions

Replace the current `get_partners/2` and `get_ex_partners/2` with:

- `get_active_partners(person_id, opts)` — fetches `married` + `relationship` types
- `get_former_partners(person_id, opts)` — fetches `divorced` + `separated` types

Both use the existing `get_relationship_partners/3` helper, passing a list of types instead of a single type.

### Replace `convert_to_ex_partner/2`

Remove the delete+recreate transaction. Replace with `update_partner_type(relationship, new_type, metadata_attrs)`:

- In-place update of `type` and `metadata`
- Supports any type transition (e.g. `married` → `divorced`, `relationship` → `separated`, `separated` → `married`)
- Check for unique constraint conflict (same pair already has a relationship of the target type) and return a clear error

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
   - **Separated**: separated date (day/month/year)

### Remove Convert-to-Ex Modal

The "Convert to Ex-Partner" modal and its assigns (`converting_to_ex`, `ex_form`) are removed. Functionality absorbed into the edit relationship modal.

## Add Relationship Component

When `relationship_type == "partner"`, the metadata step shows:

1. A **type dropdown** (Married, Relationship, Divorced, Separated) — default: **"Relationship"**
2. Metadata fields that change dynamically based on selected type (same field sets as the edit modal)

On save, passes the selected type (e.g. `"married"`) to `create_relationship/4` instead of always `"partner"`.

`build_relationship_form/2` initializes with `partner_subtype: "relationship"` as default.

## Tree View (`PersonTree`)

`build_family_unit_full/3` replaces `get_partners` → `get_active_partners` and `get_ex_partners` → `get_former_partners`.

No structural change to tree data — active types feed into partner sorting + previous partners, former types feed into ex-partner groups. The tree template's `data-previous-separator` (solid) and `data-ex-separator` (dashed) still apply correctly.

## FamilyEcho Import

- `{:partner, ...}` → `{:relationship, ...}`
- `{:ex_partner, ...}` → `{:separated, ...}`

The CSV orchestrator passes type as `Atom.to_string(type)` to `create_relationship/4`, so this flows through cleanly.

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
- User flow tests exercising partner add/edit/convert workflows
