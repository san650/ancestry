# Compact People Table Design

## Overview

Refactor PeopleLive.Index from flex rows to a compact CSS grid table with column headers, add actions column (edit, remove), make name clickable, and update PersonLive.Show back navigation to return to the people page.

## CSS Grid Table Layout

Replace flex rows with CSS grid. Responsive:

**Desktop (sm+):** Column headers visible, full grid:
`[checkbox?] [photo] [name] [lifespan] [relationships] [actions]`

**Mobile (<sm):** Lifespan and relationships collapse under the name (stacked). Actions column stays as icon-only buttons. Column headers hidden.

### Compact sizing
- Photo: 32px (down from 40px)
- Row padding: `py-1.5` (down from `py-3`)
- Text: `text-sm` base, `text-xs` for secondary info
- Remove `max-w-4xl` constraint — let table use full page width with padding
- Select all/deselect all integrates into the table header row

## Actions Column

Last column, right-aligned, icon-only buttons:

- **Edit:** `hero-pencil` icon. Navigates to `/people/:id?from_family=:family_id&from_people=true&editing=true`
- **Remove:** `hero-x-mark` icon. Selects this person and opens the existing confirmation modal (reused)

## Name as Link

Name text becomes `<.link navigate={...}>` to `/people/:id?from_family=:family_id&from_people=true` (view mode).

## PersonLive.Show Changes

### New query params
- `from_people=true` — back button goes to `/families/:family_id/people` instead of tree view
- `editing=true` — auto-enters edit mode on mount

### Back navigation logic
- When `@from_people` is true: back button navigates to `/families/:family_id/people`
- Otherwise: current behavior (`/families/:family_id?person=:person_id`)

### person_path helper
When `@from_people` is true, the `person_path/2` helper preserves `from_people=true` so navigation within PersonLive.Show maintains the back context.

## Testing

Update `test/user_flows/manage_people_test.exs`:

### New test cases
1. **Click name navigates to person show** — verify navigation and back button visible
2. **Back button returns to people page** — verify return to `/families/:family_id/people`
3. **Edit action navigates to person show in edit mode** — verify edit mode active
4. **Remove action on single row** — verify confirmation modal, confirm removal

### Existing tests to update
- "view people table" test updated for new column layout (actions column)
