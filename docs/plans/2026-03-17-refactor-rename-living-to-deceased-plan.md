---
title: "Rename Person.living to Person.deceased"
type: refactor
status: active
date: 2026-03-17
origin: docs/brainstorms/2026-03-17-rename-living-to-deceased-brainstorm.md
---

# Rename Person.living to Person.deceased

## Overview

Replace the `Person.living` string field (`"yes"`, `"no"`, `"unknown"`) with a `Person.deceased` boolean field (`true`/`false`). This simplifies the data model, removes the ambiguous "unknown" state, and aligns the field semantics with the UI display convention (`d. 1994`).

## Problem Statement / Motivation

The current `living` field uses inverted semantics — asking "is living?" rather than "is deceased?" — with a three-value string that adds unnecessary complexity. A boolean `deceased` field is simpler, more intuitive, and directly supports the `d.` display indicator. The "unknown" state provides no actionable value and is better treated as "living" (the common default).

(see brainstorm: `docs/brainstorms/2026-03-17-rename-living-to-deceased-brainstorm.md`)

## Proposed Solution

Multi-step safe migration with atomic deployment:

1. **Migration 1:** Add `deceased` boolean column, backfill from `living`, add NOT NULL
2. **Code update:** Update schema, changeset, templates, CSV import, tests
3. **Migration 2:** Drop the `living` column

All three steps deploy together — `mix ecto.migrate` runs both migrations before the app starts.

## Data Migration Mapping

| `living` value | `deceased` value |
|----------------|------------------|
| `"yes"`        | `false`          |
| `"no"`         | `true`           |
| `"unknown"`    | `false`          |

**Note:** The distinction between "living" and "unknown" is permanently lost. This is an accepted trade-off (see brainstorm).

## Implementation Steps

### Step 1: Migration — Add `deceased` column and backfill

Generate with `mix ecto.gen.migration add_deceased_to_persons`.

```elixir
# priv/repo/migrations/TIMESTAMP_add_deceased_to_persons.exs
defmodule Ancestry.Repo.Migrations.AddDeceasedToPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      add :deceased, :boolean, default: false
    end

    flush()

    execute(
      "UPDATE persons SET deceased = true WHERE living = 'no'",
      "UPDATE persons SET living = 'no' WHERE deceased = true"
    )

    alter table(:persons) do
      modify :deceased, :boolean, null: false, default: false
    end
  end
end
```

### Step 2: Update Person schema

**File:** `lib/ancestry/people/person.ex`

- Remove `field :living, :string, default: "yes"`
- Add `field :deceased, :boolean, default: false`
- Update `@cast_fields`: replace `:living` with `:deceased`
- Remove `validate_inclusion(:living, ~w(yes no unknown))`
- No new validation needed — Ecto's boolean cast rejects non-boolean values

### Step 3: Update CSV import — FamilyEcho adapter

**File:** `lib/ancestry/import/csv/family_echo.ex`

- Rename `parse_living/1` → `parse_deceased/1`
- Change return values: `"Y"` → `true`, `_` → `false`
- Update map key in `parse_person/1`: `living: parse_living(...)` → `deceased: parse_deceased(...)`

### Step 4: Update CSV import — field list

**File:** `lib/ancestry/import/csv.ex`

- In `@import_fields` (line ~102): replace `:living` with `:deceased`
- This is critical for re-import change detection to work correctly

### Step 5: Update new person form

**File:** `lib/web/live/person_live/new.html.heex`

Replace the living select (lines ~83-88) with:

```heex
<.input
  field={@form[:deceased]}
  type="select"
  label="Deceased"
  options={[{"No", "false"}, {"Yes", "true"}]}
/>
```

Default is `false` from schema, so "No" is pre-selected.

### Step 6: Update show page — edit form and detail display

**File:** `lib/web/live/person_live/show.html.heex`

**Edit form** (lines ~100-105): Same select as Step 5.

**Detail display** (lines ~286-289): Replace `Living: {String.capitalize(@person.living)}` with:

```heex
<div class="...">
  <span class="...">Deceased:</span>
  <span>{if @person.deceased, do: "Yes", else: "No"}</span>
</div>
```

### Step 7: Update person card with `d.` indicator

**File:** `lib/web/live/person_live/show.ex` (lines ~601-633)

Add a `d.` indicator when `person.deceased` is `true`. Use HTML `title` attribute for tooltip:

```heex
<%= if @person.deceased do %>
  <span title="This person is deceased." class="text-gray-500 text-sm">
    d.{if @person.death_year, do: " #{@person.death_year}", else: ""}
  </span>
<% end %>
```

Display examples:
- `deceased: true`, `death_year: 1994` → `d. 1994`
- `deceased: true`, `death_year: nil` → `d.`
- `deceased: false` → nothing shown

The `d.` indicator appears on the card wherever `person_card` is used (relationship sections, search results in modals).

### Step 8: Migration — Drop `living` column

Generate with `mix ecto.gen.migration drop_living_from_persons`.

```elixir
# priv/repo/migrations/TIMESTAMP_drop_living_from_persons.exs
defmodule Ancestry.Repo.Migrations.DropLivingFromPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      remove :living, :text, default: "yes", null: false
    end
  end
end
```

### Step 9: Update tests

**File:** `test/ancestry/people_test.exs`
- Replace "defaults living to yes" test → "defaults deceased to false"
- Replace inclusion validation test → test that boolean `true`/`false` are accepted
- Replace invalid value test → test non-boolean rejection
- Use `Ecto.Changeset.get_field(changeset, :deceased)` for assertions

**File:** `test/ancestry/import/csv/family_echo_test.exs`
- Change `attrs.living == "yes"` → `attrs.deceased == false`
- Change `attrs.living == "no"` → `attrs.deceased == true`

**File:** `test/ancestry/import/csv_test.exs`
- Change `person.living == "no"` → `person.deceased == true`

**File:** `test/web/live/person_live/show_test.exs`
- Change `living: "yes"` in setup → `deceased: false` (or remove, since `false` is the default)
- Add test for `d.` indicator: create person with `deceased: true, death_year: 2020`, render page, assert `d. 2020` is present with correct `title` attribute

### Step 10: Run `mix precommit`

Run `mix precommit` to verify compilation (warnings-as-errors), formatting, and all tests pass.

## Files Changed

| File | Change |
|------|--------|
| `priv/repo/migrations/new_add_deceased_to_persons.exs` | Add column, backfill, NOT NULL |
| `priv/repo/migrations/new_drop_living_from_persons.exs` | Drop `living` column |
| `lib/ancestry/people/person.ex` | `:living` string → `:deceased` boolean |
| `lib/ancestry/import/csv/family_echo.ex` | `parse_living` → `parse_deceased`, return boolean |
| `lib/ancestry/import/csv.ex` | `:living` → `:deceased` in `@import_fields` |
| `lib/web/live/person_live/new.html.heex` | Replace living select with deceased select |
| `lib/web/live/person_live/show.html.heex` | Replace living select + detail display |
| `lib/web/live/person_live/show.ex` | Add `d.` indicator to `person_card` |
| `test/ancestry/people_test.exs` | Boolean field tests |
| `test/ancestry/import/csv/family_echo_test.exs` | Boolean assertions |
| `test/ancestry/import/csv_test.exs` | Boolean assertions |
| `test/web/live/person_live/show_test.exs` | Update setup + add `d.` indicator test |

**Files confirmed unchanged:**
- `lib/web/live/person_live/quick_create_component.ex` — uses schema default, no `living` reference
- `lib/ancestry/people.ex` — context delegates to changeset, no direct field reference
- `lib/ancestry/import/csv/adapter.ex` — loosely typed behaviour callback

## Acceptance Criteria

- [ ] `deceased` boolean column exists with default `false`, NOT NULL
- [ ] `living` column is dropped
- [ ] Existing data is correctly migrated (`"no"` → `true`, `"yes"`/`"unknown"` → `false`)
- [ ] Person creation form shows "Deceased" select with "No"/"Yes" (default "No")
- [ ] Person edit form shows same select
- [ ] Person detail view shows "Deceased: Yes" or "Deceased: No"
- [ ] Person card shows `d.` with tooltip when deceased, with death year if available
- [ ] Person card shows nothing when not deceased
- [ ] CSV import maps `"Y"` → `true`, else → `false`
- [ ] CSV re-import detects changes to `deceased` field
- [ ] All existing tests pass with updated assertions
- [ ] New test for `d.` indicator on person card
- [ ] `mix precommit` passes clean

## Sources

- **Origin brainstorm:** [docs/brainstorms/2026-03-17-rename-living-to-deceased-brainstorm.md](docs/brainstorms/2026-03-17-rename-living-to-deceased-brainstorm.md) — key decisions: boolean type, value mapping, multi-step migration, `d.` indicator format
- **SpecFlow findings:** Detail view must use conditional display (not `String.capitalize` on boolean); `@import_fields` update is critical for re-import; `quick_create_component.ex` needs no changes
