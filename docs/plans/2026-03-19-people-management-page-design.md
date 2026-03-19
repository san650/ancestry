# People Management Page Design

## Overview

A new page inside the family scope that lists all family members in a table with search, read/edit modes, and bulk removal. Accessed via a "Manage people" toolbar button on FamilyLive.Show.

## Route & LiveView

- **Route:** `/families/:family_id/people`
- **LiveView:** `Web.PeopleLive.Index` at `lib/web/live/people_live/index.ex` with colocated `index.html.heex`
- **Navigation:** "Manage people" button in FamilyLive.Show toolbar (between Kinship and Edit). Back arrow in PeopleLive toolbar navigates to `/families/:family_id`.

### Assigns

| Assign | Type | Purpose |
|--------|------|---------|
| `:family` | Family struct | Loaded family |
| `:people` | stream | Streamed list of `{person, relationship_count}` |
| `:people_empty?` | boolean | Empty state tracking |
| `:filter` | string | Current search query |
| `:editing` | boolean | Read/edit mode toggle |
| `:selected` | MapSet | Selected person IDs for bulk operations |
| `:confirm_remove` | boolean | Controls confirmation modal visibility |

## Data Loading

### New query: `People.list_people_for_family_with_relationship_counts/1`

Returns `{person, relationship_count}` tuples. Single SQL query: joins `family_members` to get people, left-joins `relationships` where both `person_a_id` and `person_b_id` belong to the family, groups by person, counts relationships. Default sort: `surname ASC, given_name ASC`.

### Filtered variant: `People.list_people_for_family_with_relationship_counts/2`

Accepts a search term. Applies diacritics-insensitive `unaccent() ILIKE` on `given_name`, `surname`, and `nickname`.

## UI Layout

### Toolbar

- **Left:** Back arrow + "Family Name — People" title
- **Right:** "Edit" button (toggles edit mode). In edit mode with selections: "Remove from family" button.

### Search box

Full-width input below toolbar with search icon, placeholder "Search people...", `phx-change` with 300ms debounce.

### Table columns

| Column | Details |
|--------|---------|
| Checkbox | Edit mode only. `toggle_select` event with person ID. Header has select all/deselect all. |
| Photo | 40px circular thumbnail via `PersonPhoto.url/2` `:thumbnail`, fallback `hero-user` icon |
| Name | "Surname, Given Names" format. If surname blank, just given name. |
| Lifespan | "birth_year – death_year". Dim "deceased" text when `person.deceased == true`. Dash or empty for nil years. |
| Relationships | Count number, or "not connected" badge when 0 |

### Empty state

Centered message when no people in family, with link back to add members.

### Confirmation modal

Standard Phoenix modal. "Remove N people from this family?" with Cancel and red "Remove" button.

## Events

| Event | Payload | Action |
|-------|---------|--------|
| `filter` | `%{"filter" => query}` | Re-fetch filtered people, stream `reset: true`, clear selections |
| `toggle_edit` | — | Toggle `@editing`, clear `@selected` when exiting edit mode |
| `toggle_select` | `%{"id" => person_id}` | Add/remove from `@selected` MapSet |
| `select_all` | — | Add all visible person IDs to `@selected` |
| `deselect_all` | — | Clear `@selected` |
| `request_remove` | — | Show confirmation modal |
| `cancel_remove` | — | Hide confirmation modal |
| `confirm_remove` | — | Remove selected people via `People.remove_from_family/2`, re-fetch, stream `reset: true`, clear selections, close modal, stay in edit mode, flash message |

## Testing

File: `test/user_flows/manage_people_test.exs` — LiveView integration tests.

### Test cases

1. **View people table** — Given family with people (some with relationships, some without), verify table shows correct names, lifespans, relationship counts, and "not connected" tags.

2. **Search/filter people** — Type in search box, verify table narrows. Verify diacritics-insensitive matching ("jose" matches "Jose").

3. **Enter and exit edit mode** — Click Edit, verify checkboxes appear. Click Done, verify checkboxes disappear and selections clear.

4. **Select and remove people from family** — In edit mode, select 2 people, click "Remove from family", confirm in modal, verify removal from table, page stays in edit mode, flash message shown.

5. **Navigate from family show** — Click "Manage people" in toolbar, verify navigation to people management page.
