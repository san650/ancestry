# Birthday Calendar

## Summary

A vertical birthday calendar page, family-scoped, that lists all family members with known birthdays ordered January through December. The page auto-scrolls to today's date, fades past birthdays, and highlights upcoming ones — making it easy to see at a glance who has a birthday coming up.

## Route

`/org/:org_id/families/:family_id/birthdays` — inside the existing `:organization` live_session.

## Data

### Source

The `Person` schema stores birth dates as separate integer fields: `birth_day`, `birth_month`, `birth_year`. A person appears on the calendar only if both `birth_month` and `birth_day` are present. `birth_year` is optional — when present, the age is computed; when absent, no age is shown.

### Query

A new function `Ancestry.People.list_birthdays_for_family(family_id)` returns people with both `birth_month` and `birth_day` set, ordered by `(birth_month, birth_day)`. Fields needed: `id`, `given_name`, `surname`, `birth_day`, `birth_month`, `birth_year`, `deceased`, `photo`, `photo_status`, `gender`.

### Grouping

The LiveView groups results into 12 month buckets (January–December). All 12 months are always shown. Empty months display a subtle "No birthdays" placeholder.

## UI Design

### Layout

- **Mobile-first** vertical list
- **Month headers**: sticky, Manrope bold, tonal background. Past months use reduced opacity (0.5 on the header text)
- **Person entries**: cards stacked vertically within each month section

### Person card structure

```
┌─────────────────────────────────────────────┐
│ ┌──────┐  ┌──┐                              │
│ │  8   │  │👤│  Pedro Sánchez               │
│ │ Mar  │  │  │  Turned 45                   │
│ └──────┘  └──┘                              │
└─────────────────────────────────────────────┘
```

Left to right:
1. **Date box** — rounded rectangle, `dce9ff` background. Large day number (18px bold), short month abbreviation below (9px uppercase)
2. **Person photo** — 36px circular avatar (or icon placeholder with gender color)
3. **Name + age** — name on first line (13px medium), age on second line (11px muted)

### Age display

- **Living, past birthday this year**: "Turned X"
- **Living, upcoming birthday**: "Turns X"
- **Deceased**: "Would have turned X" with a `(deceased)` tag next to the name
- **No birth year**: age line omitted

Age is calculated as `current_year - birth_year`, adjusted for whether the birthday has passed this year.

### Today marker

A green horizontal divider between the last past entry and the first upcoming entry:

```
────── TODAY · APR 15 ──────
```

- Color: `#006d35` (the design system success color)
- Positioned between entries based on the current date, even mid-month
- **Today's birthdays** render **below** the marker at full opacity with "Turns X today!" text — they are the highlight, not faded

### Past/future distinction

- **Past entries** (birthday already happened this year): `opacity: 0.45` on the entire card
- **Future entries**: full opacity
- **Past month headers**: header text at `opacity: 0.5`

### Auto-scroll

On mount (connected), a JS hook scrolls the today marker into view. If there are no future birthdays (late December), scroll to the last entry.

### Empty months

Months with no birthdays show:

```
┌─────────────────────────────────┐
│  February                       │
│                                 │
│  No birthdays                   │
│                                 │
└─────────────────────────────────┘
```

Subtle muted text, centered or left-aligned within the month section.

### Navigation

- **Entry point**: a "Birthdays" link in the meatball menu on the family show page, using `hero-cake` icon. Placed after "Manage people" and before "Create subfamily".
- **Person tap**: clicking a person card navigates to `/org/:org_id/people/:person_id?from_family=:family_id`
- **Back**: standard back navigation to family show

## Components

### LiveView: `Web.BirthdayLive.Index`

- `mount/3`: loads family, verifies org ownership, queries birthdays, groups by month, computes today marker position
- `render/1`: iterates over 12 months, renders sticky headers, person cards, today divider, and empty-month placeholders
- No real-time updates needed (birthdays don't change frequently)

### JS Hook: `ScrollToToday`

- Attached to the today marker element
- On `mounted`, scrolls the element into view with `behavior: "smooth"` and a small top offset

### Context function: `Ancestry.People.list_birthdays_for_family/1`

- Queries `persons` joined through `family_members`
- Filters: `birth_month IS NOT NULL AND birth_day IS NOT NULL`
- Additionally filters out invalid date combinations (e.g., Feb 30, Apr 31) by clamping `birth_day` to the max days for `birth_month` (using 29 for February to include leap-day birthdays)
- Orders by: `birth_month ASC, birth_day ASC`
- Returns plain `Person` structs

## Age computation

Computed in the LiveView (not the database) as a helper function:

```
compute_age(birth_year, birth_month, birth_day, today) ->
  base_age = today.year - birth_year
  if {today.month, today.day} < {birth_month, birth_day}, do: base_age - 1, else: base_age
```

For the "turns/turned" label:
- `{birth_month, birth_day} < {today.month, today.day}` → past → "Turned X"
- `{birth_month, birth_day} == {today.month, today.day}` → today → "Turns X today!"
- `{birth_month, birth_day} > {today.month, today.day}` → future → "Turns X"

### Edge cases

- **Leap day (Feb 29)**: In non-leap years, treat Feb 29 birthdays as Feb 28 for past/future comparison. They still display as "Feb 29" on the card.
- **Invalid dates (Feb 31, etc.)**: Filtered out at query time (see context function above).
- **Internationalization**: All month names, age labels ("Turned", "Turns", "Would have turned"), and UI text use `gettext` for i18n support. Month names use `Cldr` or a simple gettext-based month name map.
- **Authorization**: Uses the same `Web.EnsureOrganization` on_mount hook as other family-scoped pages. No additional Permit setup needed — this is a read-only view with no actions to authorize beyond page access.

## E2E tests

Per project conventions, tests go in `test/user_flows/birthday_calendar_test.exs`:

- View birthday calendar with people across multiple months
- Empty month placeholder shown for months with no birthdays
- Deceased person shows "(deceased)" tag
- People without `birth_month`/`birth_day` are excluded
- Clicking a person navigates to their profile
- Today marker is rendered in the correct position
- Past entries have faded styling
