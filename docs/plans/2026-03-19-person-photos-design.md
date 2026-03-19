# Person Photos Design

Show all photos where a person is tagged in a masonry gallery on their show page, with full lightbox support including comments and tagging.

## Decisions

- Photo gallery sits **below the relationships section** at the bottom of the person show page
- Lightbox cycles only through the **person's tagged photos**, not all system photos
- Lightbox opens as a **full-page overlay on the person show page** — closing returns to person show
- Masonry grid shows **clean photos with no metadata labels**

## Approach: Extract Shared Components

Extract reusable pieces from `GalleryLive.Show` so both gallery and person pages share a single source of truth.

## Data Layer

No new schemas or migrations. Add one query function:

**`Ancestry.Galleries.list_photos_for_person(person_id)`** — returns all photos where the person is tagged via `photo_people`, filtered to `status: "processed"`, ordered by `inserted_at desc`. Crosses all galleries and families.

## Shared Components

### `Web.Components.PhotoGallery`

Function component module extracted from `GalleryLive.Show`:

| Component | Renders | Key assigns |
|---|---|---|
| `photo_grid/1` | Masonry grid of thumbnails with click handler | `photos` (stream), `grid_layout` |
| `lightbox/1` | Full-screen overlay: image, nav arrows, side panel (people + comments), thumbnail strip | `selected_photo`, `photos` (list), `panel_open`, `photo_people` |

Gallery-specific concerns stay in `GalleryLive.Show`: upload form, drag-drop, upload modal, selection mode, delete confirmation.

JS hooks (`PhotoTagger`, `PersonHighlight`) and `PhotoCommentsComponent` are already standalone — no changes needed.

### `Web.PhotoInteractions`

Helper module for shared lightbox event handling. Both LiveViews delegate to it:

- `open_photo/2` — loads photo + photo_people, pushes to JS
- `close_lightbox/1` — cleans up subscriptions, clears selected_photo
- `navigate_lightbox/3` — prev/next using a caller-provided photo list function
- `select_photo/2` — thumbnail strip selection
- `toggle_panel/1` — open/close side panel with comment subscription management
- `tag_person/4`, `untag_person/3` — create/delete photo_people records
- `search_people_for_tag/2` — search all people
- `highlight_person/2`, `unhighlight_person/2` — push highlight events to JS
- `push_photo_people/1` — push people data to PhotoTagger hook
- `handle_comment_info/2` — forward comment PubSub to PhotoCommentsComponent

Each LiveView's `handle_event` delegates to these functions. The only difference is how the photo list is sourced:
- GalleryLive: `Galleries.list_photos(gallery_id)`
- PersonLive: `Galleries.list_photos_for_person(person_id)`

## PersonLive.Show Changes

**Mount:** Add lightbox assigns (`selected_photo: nil`, `panel_open: false`, `photo_people: []`, `comments_topic: nil`). Stream person's tagged photos.

**Template:** Below relationships section, add:
- "Photos" section header with count
- `photo_grid` component (always masonry, no layout toggle)
- `lightbox` component (when `@selected_photo` is set)
- Empty state when no tagged photos

**No upload, selection, or delete functionality** — read-only gallery with tagging and commenting only.

No additional PubSub subscriptions needed — photos are already processed when they appear in the tagged list.
