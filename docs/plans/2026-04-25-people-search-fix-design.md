# People Search Fix — Cross-Field and Diacritics

**Date:** 2026-04-25
**Status:** Design

## Problem

People search fails in two scenarios:

1. **Cross-field queries:** Typing "martin v" to find "Martín Vazquez" fails because SQL `ILIKE` checks `given_name` and `surname` independently — neither field contains "martin v" as a substring.
2. **Diacritics in @mention:** Typing `@martí` in the memory vault editor fails because the JS regex `[a-zA-Z0-9 ]` blocks non-ASCII characters, so the search event is never sent to the server.

**Affected search paths:**
- `People.search_all_people/2` and `/3`
- `People.search_family_members/3`
- `People.search_people/3`
- `People.list_people_for_family_with_relationship_counts` (search clauses)
- `People.list_people_for_org` (search clauses)
- Trix editor @mention regex (`assets/js/trix_editor.js:114`)

**Not affected:** Client-side filters in `KinshipLive.filter_people/3` and `PersonSelectorComponent` — these already search against `display_name` with `StringUtils.normalize/1`.

## Solution

### 1. Denormalized `name_search` Column

Add a `name_search` text column to the `persons` table that stores a pre-computed, normalized concatenation of all searchable name fields.

#### Migration

- Add column `name_search` (`:text`, nullable) to `persons` table
- Backfill all existing rows by computing from their current name fields

#### Person Schema

- Add `field :name_search, :string`
- In `changeset/2`, after all name fields are cast, compute `name_search`:
  1. Collect `[given_name, surname, given_name_at_birth, surname_at_birth, nickname] ++ alternate_names`
  2. Reject nils and blanks
  3. Join with spaces
  4. Normalize via `StringUtils.normalize/1` (NFD decomposition, strip diacritics, downcase)
- The column is never cast from user input — always computed from other fields

#### Example

Person with: given_name "Martín", surname "Vazquez", nickname "Martincho", alternate_names ["Martín José"]

`name_search` value: `"martin vazquez martincho martin jose"`

### 2. Search Function Changes

All `search_*` functions in the `People` context replace the multi-field `unaccent()` fragment block with a single Ecto `ilike` on `name_search`.

**Before (each function):**
```elixir
where:
  fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
    fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
    fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like) or
    fragment("EXISTS (SELECT 1 FROM unnest(?) ...)", p.alternate_names, ^like)
```

**After:**
```elixir
where: ilike(p.name_search, ^like)
```

Search term normalization is handled by a new `StringUtils.normalize_sql_search/1` function.

**Functions to update:**
- `search_all_people/2`
- `search_all_people/3`
- `search_family_members/3`
- `search_people/3`
- `list_people_for_family_with_relationship_counts` (search clause)
- `list_people_for_org` (search clause)

### 3. StringUtils.normalize_sql_search/1

New function in `Ancestry.StringUtils` that normalizes a search term for SQL ILIKE queries:

```elixir
def normalize_sql_search(term) do
  escaped =
    term
    |> normalize()
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")

  "%#{escaped}%"
end
```

The existing `normalize/1` remains unchanged — it's used for in-memory filtering (kinship, person selector) and for computing the `name_search` column value.

### 4. JS Regex Fix

**File:** `assets/js/trix_editor.js:114`

The @mention regex blocks diacritics. Fix by using Unicode character classes:

**Before:**
```javascript
const match = text.match(/(?:^|[^a-zA-Z0-9])@([a-zA-Z0-9 ]{0,30})$/)
```

**After:**
```javascript
const match = text.match(/(?:^|[^\p{L}\p{N}])@([\p{L}\p{N} ]{0,30})$/u)
```

`\p{L}` matches any Unicode letter (including á, í, ó, ñ), `\p{N}` matches any Unicode digit. The `u` flag enables Unicode mode.

## Testing

### Unit tests (`test/ancestry/people_test.exs`)

- `name_search` is computed correctly from all name fields in changeset
- `name_search` updates when name fields change
- Cross-field search: "martin v" finds a person with given_name "Martín", surname "Vazquez"
- Diacritics: "martin" finds "Martín"
- Nickname search: searching a nickname finds the person
- Alternate names search: searching an alternate name finds the person

### LiveView / E2E tests (`test/user_flows/`)

- Memory vault: typing `@` + diacritics triggers suggestions
- Memory vault: typing `@` + cross-field query (given + partial surname) shows the person
- Photo tagger: cross-field search finds the person

All tests use factory-generated people with fake names.
