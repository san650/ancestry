# Person Show View Redesign

## Summary

Redesign the person show page to reduce visual clutter, eliminate data duplication, and align margins across all sections. Desktop gets a new compact header layout; mobile gets the same metadata changes but retains the current hero photo treatment.

## Problems with current design

1. **Inconsistent margins** — header uses `max-w-4xl`, relationships `max-w-5xl`, photos `max-w-7xl`. Left edges don't align.
2. **Photo placement** — on desktop the photo sits inside a flex layout with large gap, not flush with the content margin.
3. **Redundant data** — name appears in toolbar AND in content. "Deceased: Yes" shown even when death date is present. Section headers ("Name", "Details", "Families") add noise without value.
4. **Scattered layout** — name fields, details, and families are separate sections with uppercase headers, making simple data feel like a complex form.

## Design decisions

### Unified width

All sections use `max-w-4xl mx-auto` with consistent horizontal padding (`px-4 sm:px-6 lg:px-8`). This applies to:
- Person header (photo + vitals)
- Extra metadata row
- Relationships section
- Photos section

**Note:** The photos section currently uses `max-w-7xl` (1280px). Reducing to `max-w-4xl` (896px) means fewer photo grid columns on desktop (~4 instead of ~6). This is an intentional trade-off for consistent left-edge alignment across the page.

### Desktop header layout (Option C — two-line vitals + overflow)

**Always next to photo (right of `lg:w-48 lg:h-48` / 192×192px image — unchanged from current):**
- Birth/death dates (see date display logic below)
- Gender
- Family chips: `In family trees` label + linked `@person.families` chips

**Below photo (only when extra fields exist):**
- Single-column key-value grid (label left, value right, `max-width: 280px`)
- Fields shown only when populated: nickname, title, suffix, birth given name (if differs from current), birth surname (if differs from current)
- AKA names (`@person.alternate_names`) as inline chips below the grid — guard against `nil` (schema default is `[]` but column is nullable)
- When none of these extra fields are populated, this entire row does not render. The layout is just the photo + vitals flex row.

**Removed from content:**
- Person name (already in toolbar)
- "Name" section header
- "Details" section header
- "Families" section header
- "Deceased: Yes/No" row (redundant when death date shown; if no death date but deceased, the date line says "deceased")

### Mobile changes

Same metadata simplification as desktop:
- Remove name from content body (already shown as overlay on hero photo)
- Remove section headers ("Name", "Details", "Families")
- Remove "Deceased: Yes/No" redundancy
- Same date formatting logic
- Family chips inline after gender
- Extra fields below as single-column key-value list when present

**No change to mobile photo treatment** — keep the full-width hero image with name overlay.

### Date display logic

The `b.` and `d.` prefixes wrap the existing `format_partial_date/3` helper output, which handles nil day/month/year independently. Examples: `b. 1917`, `b. 03/1917`, `b. 29/03/1917` are all valid depending on available data. The `deceased` flag is the `@person.deceased` boolean schema field.

| State | Display |
|-------|---------|
| Has birth date, has death date | `b. {date} — d. {date}` |
| Has birth date, deceased, no death date | `b. {date} — deceased` |
| Has birth date, alive | `b. {date}` |
| No birth date, has death date | `d. {date}` |
| No birth date, deceased, no death date | `Deceased` |
| No dates, alive | *(nothing)* |

### Files to modify

- `lib/web/live/person_live/show.html.heex` — main template changes
- `lib/web/live/person_live/show.ex` — new helper for combined date display line
- `test/web/live/person_live/show_test.exs` — update assertions that check for "Deceased:" text (lines 85-99) to match new date display format

### Files NOT modified

- Relationships section markup (only its container max-width changes)
- Photos section markup (only its container max-width changes)
- Edit form
- Mobile nav drawer, FAB, modals
- `show.ex` event handlers
- Existing `format_partial_date/3` helper (still used by relationship marriage/divorce dates)
