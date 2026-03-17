# Quick Create Person From Relationship Modal

## Problem

When adding parents, children, or spouses to a person on the person show screen, users can only search and link existing family members. There is no way to create a new person inline — users must leave the page, create the person separately, then return to link them.

## Solution

Add a "Create new person" option to the existing Add Relationship modal. Implemented as a LiveComponent that replaces the search view within the modal. The component collects just given name and surname, creates the person, then feeds them into the existing metadata/save flow.

## Decisions

- **"Create new" link placement:** Always visible below search results (not gated on empty results)
- **Modal behavior:** Replaces search view (not inline alongside it), with "Back to search" link
- **Post-create flow:** Auto-proceeds to the metadata step (father/mother role, marriage date, etc.) — same as selecting an existing person
- **Family membership:** New person is automatically added to the current family via `People.create_person/2`
- **Surname pre-fill:** None — both fields start blank

## Design

### QuickCreateComponent

`PersonLive.QuickCreateComponent` — a LiveComponent rendered inside the Add Relationship modal.

**Stable ID:** `"quick-create-person"` (not dynamic, per project learnings on LiveComponent IDs).

**Assigns:**
- `family` — current family (for `People.create_person/2`)
- `form` — `to_form` changeset with `:given_name` and `:surname`
- `relationship_type` — for contextual labeling (e.g., "Create new parent")

**Form:** Two fields, both blank. Given name is required, surname is optional. Uses `People.change_person/2` for validation.

**On save:** Calls `People.create_person(family, %{given_name: ..., surname: ...})`. On success, sends `{:person_created, person, relationship_type}` to the parent LiveView. On error, shows inline validation errors.

### Parent LiveView Changes (PersonLive.Show)

**New assign:** `:quick_creating` — boolean, default `false`.

**New events:**
- `"start_quick_create"` — sets `quick_creating: true`
- `"cancel_quick_create"` — sets `quick_creating: false`
- `handle_info({:person_created, person, type})` — sets `quick_creating: false`, sets `selected_person` to the new person, generates metadata form (reuses existing `select_person` logic)

**Reset:** `cancel_add_relationship` resets `quick_creating: false` along with all other relationship-adding state.

### Template Changes (show.html.heex)

In the Add Relationship modal:
1. "Person not listed? Create new" link below search results, fires `"start_quick_create"`
2. When `@quick_creating` is true, render `QuickCreateComponent` in place of search
3. Component includes "Back to search" link that fires `"cancel_quick_create"` on the parent

### No Changes To

- `save_relationship` event handler
- Metadata form generation logic
- `load_relationships/2`
- `People` or `Relationships` contexts
