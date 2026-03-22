# Org-Level Manage People

## Summary

Create a "Manage People" page at the organization level (`/org/:org_id/people`) that shows all people belonging to the organization. Mirrors the family-level `PeopleLive.Index` but with org-scoped queries, permanent delete instead of detach, and a "No family" filter instead of "Unlinked."

## 1. Route & Navigation

- New route: `live "/people", OrgPeopleLive.Index, :index` inside the existing `:organization` live_session scope at `/org/:org_id`.
- A "People" button in the `FamilyLive.Index` toolbar (the org landing page at `/org/:org_id`) navigates to this page.

## 2. Context Layer

### `People.list_people_for_org/1,2,3`

Query all people from the `persons` table where `organization_id` matches. Returns `{person, rel_count}` tuples.

Function heads (matching the family-level overload pattern):
- `list_people_for_org(org_id)` — all people, no filter
- `list_people_for_org(org_id, opts)` when `opts` is a keyword list — supports `no_family_only: true`
- `list_people_for_org(org_id, search_term)` when `search_term` is a binary — diacritics-insensitive search on `given_name`, `surname`, `nickname` (consistent with family-level; `alternate_names` is not searched here)
- `list_people_for_org(org_id, search_term, opts)` — search + options

**Base query:** `FROM persons WHERE organization_id = ? LEFT JOIN relationships ON person_a_id = p.id OR person_b_id = p.id`, grouped by `person.id`, selecting `{person, COUNT(DISTINCT r.id)}`. This is a new `base_org_people_query/1` private function — simpler than the family-level version since there's no family-scoped relationship filtering.

**"No family" filter:** Additional `LEFT JOIN family_members ON family_members.person_id = persons.id`, then `HAVING COUNT(DISTINCT family_members.family_id) = 0`.

### `People.delete_people/1`

Accepts a list of person IDs. Fetches each person via `get_person!/1` (needed for the struct), then calls `delete_person/1` for each (which handles file cleanup and relies on DB cascade rules for relationships and family_members). Wrapped in a `Repo.transaction`.

## 3. LiveView Module — `Web.OrgPeopleLive.Index`

Module name deliberately diverges from the `___Live.Index` pattern (e.g., `PeopleLive.Index`) to avoid clashing with the existing family-scoped `PeopleLive.Index`. Files live under `lib/web/live/org_people_live/`.

### Mount

- Loads all org people via `People.list_people_for_org(org.id)` where `org` comes from `@organization` (set by `EnsureOrganization` on_mount)
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
| `request_delete_one` | Set `selected` to just that person's ID and show confirmation modal (guards against re-entry if modal already open) |
| `cancel_delete` | Close confirmation modal |
| `confirm_delete` | Call `People.delete_people/1` with selected IDs, re-stream, flash |

### Helpers

`estimated_age/1` — copy from `PeopleLive.Index` (same logic, not worth extracting to a shared module for two call sites).

### Navigation

Person name links to `PersonLive.Show` with `?from_org=true` query param.

### Template

Uses `<Layouts.app flash={@flash} organization={@organization}>` wrapper. Same grid-based table layout as family-level `PeopleLive.Index`:

- **Toolbar:** Back arrow to `/org/:org_id`, title "People", edit/done toggle, "Delete" button (visible in edit mode with selections)
- **Search + filter bar:** Search input with diacritics support, "No family" toggle chip
- **Select all/deselect all bar:** Shown in edit mode, with selection count
- **Table columns:** Photo (with deceased indicator), Name, Est. Age, Lifespan, Links (relationship count or warning icon)
- **Per-row actions (non-edit mode):** Edit person link (`hero-pencil-square` icon, navigates to `PersonLive.Show` with `?from_org=true&edit=true`), delete person button (`hero-trash` icon with title "Delete person", triggers `request_delete_one` — permanent delete, not detach like the family-level `hero-link-slash`)
- **Confirmation modal:** Strong wording — "Permanently delete X people? This cannot be undone. All their photos, relationships, and family links will be removed."

## 4. PersonLive.Show — Back Navigation

Initialize `from_org: false` in `mount` (alongside existing `from_family: nil`).

Handle `?from_org=true` query param in `handle_params`. When present:
- `from_org` assign is set to `true`
- Back arrow navigates to `/org/:org_id/people` (using `@organization.id`, available from `EnsureOrganization` on_mount)

`from_family` and `from_org` are mutually exclusive — only one should be set.

Refactor the existing `confirm_delete` handler from `if/else` to `cond` with three branches:
1. `from_family` is set — redirect to family page (existing behavior)
2. `from_org` is true — redirect to `/org/:org_id/people`
3. Neither — redirect to `/org/:org_id` (existing fallback)

## 5. FamilyLive.Index — Toolbar

Add a "People" button to the `FamilyLive.Index` page (the org landing page at `/org/:org_id`) toolbar that navigates to `/org/:org_id/people`. Styled consistently with other toolbar buttons in the app.

## 6. Tests

Add a user flow test at `test/user_flows/org_manage_people_test.exs`:

**Navigating to org people page:**
Given an organization with families and people
When the user clicks "People" on the org landing page
Then the org people page is displayed with all people in the organization

**Searching people:**
Given the org people page is displayed
When the user types a search term
Then the table filters to matching people (diacritics-insensitive)

**Filtering "No family":**
Given the org people page with some people not linked to any family
When the user clicks the "No family" chip
Then only people without family links are shown

**Bulk delete:**
Given the org people page
When the user clicks "Edit", selects multiple people, and clicks "Delete"
Then a confirmation modal appears with permanent delete warning
When the user confirms
Then the selected people are permanently deleted and removed from the table

**Back navigation from PersonLive.Show:**
Given the user navigated to a person from the org people page
When the user clicks the back arrow
Then they return to the org people page

## Files to Create

- `lib/web/live/org_people_live/index.ex`
- `lib/web/live/org_people_live/index.html.heex`
- `test/user_flows/org_manage_people_test.exs`

## Files to Modify

- `lib/web/router.ex` — add route
- `lib/ancestry/people.ex` — add `list_people_for_org/1,2,3`, `delete_people/1`
- `lib/web/live/person_live/show.ex` — handle `from_org` param, update `confirm_delete` redirect
- `lib/web/live/person_live/show.html.heex` — back navigation for org context
- `lib/web/live/family_live/index.ex` — add toolbar with "People" button (if logic needed)
- `lib/web/live/family_live/index.html.heex` — add "People" button to toolbar
