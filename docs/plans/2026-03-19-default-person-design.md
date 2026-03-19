# Default Person for a Family

## Overview

Allow families to optionally configure a default person. When navigating to a family page without a `?person=` query param, the tree auto-renders for the default person instead of showing the empty state.

## Data Model

Add an `is_default` boolean column (not null, default `false`) to the `family_members` table. Only one member per family can have `is_default = true` at a time, enforced at the application level via a transaction that clears existing defaults before setting a new one.

`FamilyMember` schema gains `field :is_default, :boolean, default: false`.

### Context functions (in People or Families context)

- `set_default_member(family_id, person_id)` — transaction: clear all `is_default` for the family, then set the target to `true`
- `clear_default_member(family_id)` — set all `is_default = false` for the family
- `get_default_person(family_id)` — return the person marked as default, or `nil`

Removing a member from the family deletes the `family_members` row, which automatically clears the default.

## Edit Family Modal

Add a filterable dropdown below the family name field:
- "None" option at the top to clear the default
- All family members listed, filterable by typing
- Pre-selects the current default person when the modal opens

On save, the handler calls `set_default_member/2` or `clear_default_member/1` based on the selection, separate from the family name changeset (since this data lives on `family_members`).

## Tree Fallback Behavior

In `handle_params/3` of `FamilyLive.Show`, when no `?person=` query param is present:
1. Look up the default person via `get_default_person(family_id)`
2. If found, populate `@focus_person` and `@tree` as if the person was selected manually
3. If not found, show the current empty state

The URL stays as `/families/:family_id` — no redirect to add `?person=`.

## Testing

User flow test covering:
- Setting a default person via the Edit Family modal
- Navigating to the family page and seeing the tree auto-rendered
- Changing the default to "None" and seeing the empty state
- Removing a default member from the family and confirming the fallback clears
