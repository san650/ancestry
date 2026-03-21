# Org-Level Manage People

## Summary

Create a "Manage People" page at the organization level (`/org/:org_id/people`) that shows all people belonging to the organization. Mirrors the family-level `PeopleLive.Index` but with org-scoped queries, permanent delete instead of detach, and a "No family" filter instead of "Unlinked."

## 1. Route & Navigation

- New route: `live "/people", OrgPeopleLive.Index, :index` inside the existing `:organization` live_session scope at `/org/:org_id`.
- A "People" button in the `OrganizationLive.Index` toolbar navigates to this page.

## 2. Context Layer

### `People.list_people_for_org/3`

Query all people where `organization_id` matches. Returns `{person, rel_count}` tuples.

- `list_people_for_org(org_id)` — all people, no filter
- `list_people_for_org(org_id, search_term)` — diacritics-insensitive search on `given_name`, `surname`, `nickname`
- `list_people_for_org(org_id, search_term, opts)` — supports `no_family_only: true` option

Relationship count: count of distinct relationships where the person is `person_a_id` or `person_b_id` (not scoped to a family).

"No family" filter: `HAVING COUNT(DISTINCT family_members.family_id) = 0` via a left join on `family_members`.

### `People.delete_people/1`

Accepts a list of person IDs. Deletes all matching people with file cleanup (`cleanup_person_files/1`), wrapped in a `Repo.transaction`.

## 3. LiveView Module — `Web.OrgPeopleLive.Index`

### Mount

- Loads all org people via `People.list_people_for_org(org_id)`
- Initializes stream `:people` with `{person, rel_count}` tuples (custom `dom_id`)
- Assigns: `filter` (string), `editing` (bool), `selected` (MapSet), `confirm_delete` (bool), `no_family_only` (bool), `people_empty?` (bool)

### Events

| Event | Behavior |
|---|---|
| `filter` | Re-query with search term + current `no_family_only` state, reset stream |
| `toggle_edit` | Toggle edit mode, clear selection, re-stream |
| `toggle_no_family` | Toggle "No family" filter, re-query, reset stream |
| `toggle_select` | Toggle a person in/out of selected MapSet |
| `select_all` | Select all currently visible people |
| `deselect_all` | Clear selection |
| `request_delete` | Show confirmation modal for bulk delete |
| `request_delete_one` | Select a single person and show confirmation modal |
| `cancel_delete` | Close confirmation modal |
| `confirm_delete` | Call `People.delete_people/1` with selected IDs, re-stream, flash |

### Navigation

Person name links to `PersonLive.Show` with `?from_org=true` query param.

## 4. Template

Same grid-based table layout as family-level `PeopleLive.Index`:

- **Toolbar:** Back arrow to `/org/:org_id`, title "People", edit/done toggle, "Delete" button (visible in edit mode with selections)
- **Search + filter bar:** Search input with diacritics support, "No family" toggle chip
- **Select all/deselect all bar:** Shown in edit mode, with selection count
- **Table columns:** Photo (with deceased indicator), Name, Est. Age, Lifespan, Links (relationship count or warning icon)
- **Per-row actions (non-edit mode):** Edit person link, delete person button
- **Confirmation modal:** Strong wording — "Permanently delete X people? This cannot be undone. All their photos, relationships, and family links will be removed."

## 5. PersonLive.Show — Back Navigation

Handle `?from_org=true` query param in `handle_params`. When present:
- `from_org` assign is set to `true`
- Back arrow navigates to `/org/:org_id/people`
- Delete redirect goes to `/org/:org_id/people`

Existing `from_family` logic is unchanged — these are separate cases.

## 6. OrganizationLive.Index — Toolbar

Add a toolbar to the organization index page with a "People" button that navigates to `/org/:org_id/people`. Styled consistently with other toolbar buttons in the app.

## Files to Create

- `lib/web/live/org_people_live/index.ex`
- `lib/web/live/org_people_live/index.html.heex`

## Files to Modify

- `lib/web/router.ex` — add route
- `lib/ancestry/people.ex` — add `list_people_for_org/3`, `delete_people/1`
- `lib/web/live/person_live/show.ex` — handle `from_org` param
- `lib/web/live/person_live/show.html.heex` — back navigation for org context
- `lib/web/live/organization_live/index.ex` — add toolbar (if template changes needed)
- Organization index template — add toolbar with "People" button
