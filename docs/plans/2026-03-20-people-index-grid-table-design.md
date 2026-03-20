# People Index CSS Grid Table

## Overview

Redesign the people index page (`Web.PeopleLive.Index`) from a flex-based list into a proper table layout using CSS Grid. Add an "estimated age" column, per-row unlink actions, a warning indicator for unlinked people, and a quick filter chip.

## Grid layout

The stream container `#people-table` becomes a CSS Grid with 6 columns (7 in edit mode):

```
/* Normal mode — 6 columns */
grid-template-columns: auto auto auto auto auto 1fr;

/* Edit mode — 7 columns (checkbox prepended) */
grid-template-columns: auto auto auto auto auto auto 1fr;
```

- Columns 1–5 (or 2–6 in edit mode): `auto` — sized to content, left-aligned
- Last column: `1fr` — stretches to fill remaining width; action content inside is right-aligned

Each streamed row div uses `display: contents` so its children participate directly in the parent grid.

### Header

A separate div above the stream container using the same `grid-template-columns`. Contains column labels:

| # | Label | Notes |
|---|-------|-------|
| 0 | (blank) | Edit mode only, checkbox column header |
| 1 | (blank) | Photo column, no header text |
| 2 | Name | |
| 3 | Est. Age | |
| 4 | Lifespan | |
| 5 | Links | |
| 6 | (blank) | Actions column, no header text |

Styling: `text-sm font-medium text-base-content/50`, bottom border, same cell padding as rows.

### Zebra striping

Since `display: contents` flattens the row div, zebra striping is applied via a CSS rule in `app.css`. Row divs use a `data-row` attribute for reliable targeting:

```css
#people-table > [data-row]:nth-child(even) > * {
  background-color: var(--color-base-200);
}
```

Background color only — no `opacity` changes (text, icons, and images remain fully opaque).

### Cell padding and alignment

All cells: `px-3 py-2.5`, vertically centered (`items-center` on the grid via `align-items: center`).

## Columns

### Photo (column 1)

40x40 rounded circle (`w-10 h-10`). Shows the person's processed photo thumbnail or a `hero-user` placeholder icon. Same as current implementation.

**Alive/deceased indicator:** A DaisyUI `indicator` badge positioned at the bottom-end of the photo circle. Small dot (e.g. `badge-xs`).

- **Alive** (`deceased == false`): light green (`badge-success`)
- **Deceased** (`deceased == true`): light gray (`badge-ghost` or `bg-base-300`)
- On hover, shows a `title` tooltip: `"Deceased"` for deceased persons, no tooltip for alive persons

### Name (column 2)

Displays `Surname, Given Name` when surname exists, otherwise just `Given Name`. Styled `font-medium text-base-content`, with `truncate` for overflow.

No lifespan sub-line (that data moves to its own column).

### Estimated Age (column 3)

Calculated via a helper function. The `deceased` boolean is the authoritative field for determining living vs deceased status.

| `birth_year` | `death_year` | `deceased` | Display |
|---|---|---|---|
| 1990 | nil | false | `~36` (current_year - birth_year) |
| 1952 | 2020 | true | `~68` (death_year - birth_year) |
| 1952 | nil | true | `—` (age unknowable without death year) |
| nil | any | any | `—` |

All computed ages use the `~` prefix since they are estimates (we only have year, not exact date).

Styled `text-sm text-base-content/60`.

### Lifespan (column 4)

| `birth_year` | `death_year` | `deceased` | Display |
|---|---|---|---|
| 1952 | 2020 | true | `b. 1952 – d. 2020` |
| 1990 | nil | false | `b. 1990` |
| 1952 | nil | true | `b. 1952` |
| nil | 2020 | true | `d. 2020` |
| nil | nil | any | `—` |

Styled `text-sm text-base-content/60`.

### Links (column 5)

Relationship count scoped to the current family (only counts relationships where both people are family members), consistent with the existing query.

- **Count > 0**: Show the bare number (e.g. `3`), no "relationships" label
- **Count == 0**: Show `hero-exclamation-triangle` icon in yellow (`text-warning`)

Styled `text-sm`.

### Actions (column 6, last)

Content right-aligned within the `1fr` cell.

- **Normal mode**: `hero-link-slash` icon button to remove the person from the family. Clicking triggers the existing confirmation modal flow for a single person. Always visible for every row regardless of relationship count (the action removes from family membership, not from relationships).
- **Edit mode**: Hidden. The bulk toolbar handles removals instead.

## Edit mode

When toggled:
- A checkbox column is prepended (column 0)
- The grid switches to 7 columns
- The header gains a blank cell for the checkbox column (the existing "Select all / Deselect all" text bar remains the primary selection control)
- Per-row actions column content is hidden
- The existing select all / deselect all bar and bulk remove toolbar remain unchanged

The grid transition between 6 and 7 columns is instant (no animation).

## Quick filter: "Unlinked" chip

### UI

A toggle chip placed next to the search input (right side of the search bar area). Shows `hero-exclamation-triangle` mini icon + "Unlinked" text.

- Inactive: `btn-ghost btn-sm`
- Active: `btn-warning btn-sm` (matches the yellow warning icon in the links column)

### Behavior

- New assign: `:unlinked_only` (boolean, default `false`)
- New event: `"toggle_unlinked"` — flips the boolean, re-fetches people, re-streams with `reset: true`
- Composes with text search: both filters apply simultaneously
- The `list_people_for_family_with_relationship_counts` query gains an optional parameter to filter to only people with 0 family-scoped relationships (using `HAVING COUNT(...) = 0` or equivalent)
- `:unlinked_only` persists across edit mode toggles, matching the behavior of `:filter`

### Empty state

When filters produce no results but the family has people, the existing empty state ("No people in this family") is shown. This is acceptable since the user can clear filters to see all people.

## Single-person removal flow

The per-row `hero-link-slash` button triggers the existing confirmation modal, but for one person:

- New event: `"request_remove_one"` with `phx-value-id={person.id}`
- Sets `@selected` to a `MapSet` with just that person's ID
- Sets `@confirm_remove` to `true`
- The existing confirmation modal and `"confirm_remove"` event handle the rest unchanged
- If a confirmation modal is already open, `"request_remove_one"` is a no-op
- This event is only functional in normal mode (button is hidden in edit mode)

## What stays the same

- Toolbar layout (back button, family name heading, Edit/Done toggle, bulk remove button)
- Search box (enhanced with the unlinked chip next to it)
- Select all / deselect all bar in edit mode
- Confirmation modal markup and behavior
- Stream-based data flow with `dom_id` function
- Empty state markup

## Files to modify

1. `lib/web/live/people_live/index.html.heex` — Template rewrite for grid layout, new columns, chip, per-row actions
2. `lib/web/live/people_live/index.ex` — New assigns (`:unlinked_only`), new events (`"toggle_unlinked"`, `"request_remove_one"`), age helper
3. `lib/ancestry/people.ex` — Add unlinked filter option to `list_people_for_family_with_relationship_counts`
4. `assets/css/app.css` — Zebra striping CSS rule for the grid
5. `test/user_flows/manage_people_test.exs` — Update tests for new table layout, filter chip, per-row unlink
