---
date: 2026-03-17
topic: rename-living-to-deceased
---

# Rename Person.living to Person.deceased

## What We're Building

Rename the `Person.living` string field (`"yes"`, `"no"`, `"unknown"`) to a `Person.deceased` boolean field (`true`/`false`). Simplify the form to a two-option select (default `false`). Update all UI screens and show a `d.` indicator with optional death year on person cards.

## Why This Approach

The current `living` field uses inverted semantics (asking "is living?" instead of "is deceased?") with a three-value string that adds unnecessary complexity. A boolean `deceased` field is simpler, more intuitive, and aligns with the `d.` display convention.

## Key Decisions

- **Data type change:** String → Boolean. Simpler, no ambiguous third state.
- **Data migration strategy:** Multi-step safe migration (add column → migrate data → update schema → drop old column). This avoids downtime and data loss.
- **Unknown mapping:** `"unknown"` → `deceased: false` (treat as living by default).
- **Value mapping:** `"yes"` (living) → `false`, `"no"` (not living) → `true`, `"unknown"` → `false`.
- **Form simplification:** Two-option select (`false`/`true` displayed as "No"/"Yes") with `false` as default. No "unknown" option.
- **Person card indicator:** Show `d.` with HTML `title` tooltip "This person is deceased." plus death year if available (e.g., `d. 1994`). Only shown when `deceased: true`.
- **CSV import update:** FamilyEcho `Deceased` column: `"Y"` → `true`, else → `false`.

## Migration Plan

1. **Migration 1:** Add `deceased` boolean column (default `false`, not null). Backfill from `living`: `"no"` → `true`, else → `false`.
2. **Code update:** Update `Person` schema, changeset, all templates, CSV import, and tests to use `deceased`.
3. **Migration 2:** Drop the `living` column.

## Files to Change

| File | Change |
|------|--------|
| `priv/repo/migrations/new_add_deceased.exs` | Add `deceased` column, backfill, not null |
| `priv/repo/migrations/new_drop_living.exs` | Drop `living` column |
| `lib/ancestry/people/person.ex` | Replace `:living` with `:deceased` boolean |
| `lib/ancestry/import/csv/family_echo.ex` | Update `parse_living` → `parse_deceased`, return boolean |
| `lib/ancestry/import/csv.ex` | Update field reference from `:living` to `:deceased` |
| `lib/web/live/person_live/new.html.heex` | Update form: boolean select for `deceased` |
| `lib/web/live/person_live/show.html.heex` | Update form + display + person card |
| `lib/web/live/person_live/show.ex` | Update `person_card` component to show `d.` indicator |
| `test/ancestry/people_test.exs` | Update tests for boolean `deceased` |
| `test/ancestry/import/csv/family_echo_test.exs` | Update CSV import tests |
| `test/ancestry/import/csv_test.exs` | Update integration test assertions |
| `test/web/live/person_live/show_test.exs` | Update LiveView test |

## Open Questions

None — requirements are fully specified.

## Next Steps

→ `/ce:plan` for implementation details
