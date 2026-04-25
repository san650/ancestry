# Add Acquaintances — Design Spec

## Summary

Extend the app so acquaintances can be created and linked from photo tagging, memory @-mentions, and the photo lightbox sidebar. Extract a reusable `QuickPersonModal` component from the family graph's quick-create flow, enhanced with gender, birth date, photo upload, and a conditional acquaintance checkbox.

## Changes

### 1. Search Scope — Include Acquaintances

`People.search_all_people/2`, `People.search_all_people/3`, and the memory `search_mentions` handler all filter to `kind == "family_member"`. Remove that filter so they return all people regardless of `kind`.

**Files:**
- `lib/ancestry/people.ex` — `search_all_people/2` and `search_all_people/3`
- `lib/web/live/memory_live/form.ex` — `search_mentions` event handler (if it applies its own filter)

### 2. QuickPersonModal LiveComponent

New component: `Web.Shared.QuickPersonModal`

**Fields:**
- Photo upload (optional) — uses `allow_upload` on the LiveComponent, same pattern as `PersonLive.New`. Creates a `ProcessPersonPhotoJob` on success. The `{:person_created, person}` message is sent immediately; photo processing is async.
- Given name (required)
- Surname
- Gender (radio: Female / Male / Other) — starts with no selection
- Birth date (day / month / year dropdowns + year input)
- Acquaintance checkbox — conditionally shown via `show_acquaintance` assign, defaults unchecked (kind = `"family_member"`)

**Assigns:**
- `show_acquaintance` (boolean) — controls checkbox visibility
- `organization_id` — required, for person creation
- `family_id` (optional) — when present, calls `People.create_person(family, attrs)` which creates a `FamilyMember` association in a transaction. When nil, calls `People.create_person_without_family(org, attrs)`.
- `prefill_name` (string, optional) — pre-populates given name from the search query

**Behavior:**
- Renders as a Phoenix `<.modal>` overlay
- Validates on change (`phx-change`), submits on `phx-submit`. Error on missing given name.
- On successful creation, sends `{:person_created, person}` message to the parent LiveView
- Parent handles context-specific follow-up (tag photo, insert mention, add relationship)

**Cancel/dismiss:** Closing the modal (X, Escape, backdrop click) sends `{:quick_person_cancelled}` to the parent. Parent clears any stored state (pending coordinates, cursor position) and returns to the previous UI state.

### 3. Photo Tag Search — "Create Person" Option

Add a "Create person" button at the bottom of the `PhotoTagger` JS hook's search results list, separated by a divider. Displays the current search query (e.g. `Create "Mar..."`). Only shown when the search query is at least 1 character.

**Flow:**
1. User clicks "Create person" in the search popover
2. JS hook hides the popover, then sends `create_person_from_tag` event with `%{"x" => x, "y" => y, "query" => query, "photo_id" => photo_id}` — coordinates travel in the event payload
3. LiveView stores `%{x: x, y: y, photo_id: photo_id}` in `pending_tag` socket assign, opens `QuickPersonModal` with `prefill_name: query`
4. On `{:person_created, person}`, verifies `pending_tag.photo_id` matches the current `selected_photo`, then calls `Galleries.tag_person_in_photo/4` with the stored coordinates. If the photo changed, applies the tag to the original `photo_id` anyway (the user's intent was clear).
5. Clears `pending_tag` assign

### 4. Photo Lightbox — "Link Person" in People Sidebar

Add a `+ Link person` dashed button below the tagged people list in the lightbox's People panel.

**Flow:**
1. User clicks "Link person"
2. An inline search input expands in the sidebar (server-rendered, not JS hook), 300ms debounce
3. Typing searches all org people via a LiveView event, excluding people already tagged in the current photo
4. Results list includes a "Create person" option at the bottom (shown when query >= 1 character)
5. Selecting an existing person calls `Galleries.tag_person_in_photo/4` with `x: nil, y: nil`
6. Clicking "Create person" opens `QuickPersonModal`; on creation, auto-links with nil coordinates
7. A cancel/close button collapses the search back to the "Link person" button

**Schema change:** `PhotoPerson.changeset/2` currently has `validate_required([:x, :y])` and range validations on both fields. Changes:
- Remove `:x` and `:y` from `validate_required`
- Make range validations conditional: only validate `0.0..1.0` range when the value is non-nil

**Upsert:** Change `Galleries.tag_person_in_photo/4` to use `Repo.insert` with `on_conflict: {:replace, [:x, :y]}, conflict_target: [:photo_id, :person_id]`. This handles:
- Normal tagging (insert with coordinates)
- Reference linking (insert with nil coordinates)
- Upgrade path: tagging an already-linked person updates their coordinates
- Re-tagging: moving an existing tag to new coordinates

The `PhotoTagger` JS hook must skip rendering tag circles for `photo_people` where `x` or `y` is nil.

**Host LiveViews:** `GalleryLive.Show` and `PersonLive.Show` (both use `PhotoInteractions` and have lightboxes).

### 5. Memory @-Mention — "Create Person" Option

Add a "Create person" button at the bottom of the Trix editor's @-mention dropdown, visually separated by a border-top divider. The button sits inside the scrollable dropdown.

**Flow:**
1. User clicks "Create person" in the mention dropdown
2. JS hook saves the current Trix cursor position (selection range), hides the dropdown, then sends `create_person_from_mention` event with `%{"query" => query}`
3. LiveView opens `QuickPersonModal` with `prefill_name: query`
4. On `{:person_created, person}`, pushes a `mention_created` JS event with `%{id: person.id, name: display_name}`
5. Trix hook receives the event and inserts the mention attachment at the saved cursor position. If the saved position is invalid (out of bounds or document changed), inserts at the end of the document.

**Cancel:** On `{:quick_person_cancelled}`, LiveView pushes a `mention_cancelled` JS event. The Trix hook clears the saved cursor position.

### 6. Family Graph — Replace Quick-Create with QuickPersonModal

Replace the current 2-field (given name + surname) quick-create step in `AddRelationshipComponent` with `QuickPersonModal`.

**Config:** `show_acquaintance: false`, `family_id: family.id`

The existing `AddRelationshipComponent` flow (search existing person → or create new) stays the same; only the create-new step changes to use the richer modal.

**Cancel:** On `{:quick_person_cancelled}`, returns to the `:search` step of `AddRelationshipComponent`.

## Coordinate-less Photo Links

`PhotoPerson` records with `x: nil, y: nil` represent "reference links" — the person is associated with the photo but has no visual position.

- **People sidebar:** Reference-linked people look identical to coordinate-tagged people (same avatar, name, unlink button)
- **Tag circles:** `PhotoTagger` JS skips rendering circles for nil-coordinate records
- **Upgrade path:** If a user clicks on the photo and tags an already-linked person, the upsert in `tag_person_in_photo/4` updates the existing record with the new coordinates

## i18n

New user-facing strings: "Create person", "Link person", "Create \"%{query}\"...", acquaintance checkbox label. Run `mix gettext.extract --merge` after implementation and provide Spanish translations.

## Out of Scope

- Differentiating acquaintances visually in search results (no badge or label)
- Filtering acquaintances out of any existing views (they already appear in people indexes with the toggle)
- Changes to the full `PersonFormComponent` used on the standalone person pages
- `search_family_members/3` — remains filtered to `kind == "family_member"` (acquaintances should not appear in family graph relationship search)
