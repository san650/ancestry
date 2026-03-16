# Photo Comments Design

## Overview

Add the ability to comment on photos. Comments appear in a side panel within the lightbox view, with real-time updates via PubSub. Comments are anonymous for now (no author) — user accounts will be added later.

## Data Model

**Schema:** `Ancestry.Comments.PhotoComment`
**Table:** `photo_comments`

| Field | Type | Notes |
|-------|------|-------|
| id | integer (PK) | auto |
| text | string (text column) | required, non-empty |
| photo_id | references photos | required, FK with on_delete: delete_all |
| inserted_at | utc_datetime | auto |
| updated_at | utc_datetime | auto |

Index on `photo_id`. `Photo` schema gets `has_many :photo_comments`.

## Context — `Ancestry.Comments`

**Module:** `lib/ancestry/comments.ex`
**Schema:** `lib/ancestry/comments/photo_comment.ex`

Public API:

- `list_photo_comments(photo_id)` — returns comments ordered oldest first
- `get_photo_comment!(id)` — gets a single comment or raises
- `create_photo_comment(attrs)` — creates comment, broadcasts `{:comment_created, comment}`
- `update_photo_comment(comment, attrs)` — updates text, broadcasts `{:comment_updated, comment}`
- `delete_photo_comment(comment)` — deletes, broadcasts `{:comment_deleted, comment}`

Changeset casts `text` only. `photo_id` is set programmatically (not in cast). Validates text is required and non-empty.

Dedicated context (not in Galleries) to support future comment types on other entities.

## LiveComponent — `Web.Comments.PhotoCommentsComponent`

**Module:** `lib/web/live/comments/photo_comments_component.ex`

Receives `photo_id` from the lightbox. Manages:

- `@streams.comments` — streamed comment list
- `@form` — new comment form
- `@editing_comment_id` / `@edit_form` — inline edit state
- `@subscribed_topic` — tracks current PubSub subscription for resubscription on photo change

Events: `save_comment`, `delete_comment`, `edit_comment`, `save_edit`, `cancel_edit`.

UI: Header with close button, scrollable comment list (oldest first) with edit/delete on hover, sticky input at bottom.

## Lightbox Integration

**New assign:** `@comments_open` (boolean, default false).

**New events:**
- `toggle_comments` — flips `@comments_open`
- `close_comments` — sets false (from component's close button)

**Template changes:**
- Toggle button in lightbox top bar (chat icon)
- When open: image area shrinks, comments panel takes right side. On small screens, panel overlays.
- LiveComponent mounted with `:if={@comments_open}`

Closing the lightbox also resets `@comments_open` to false. Photo navigation keeps panel open — component receives new `photo_id` and reloads.

## Real-Time & PubSub

**Topic:** `"photo_comments:#{photo_id}"`

Broadcasts from `Ancestry.Comments` context on create/update/delete.

**Subscription managed by parent LiveView** (`GalleryLive.Show`):
- Subscribes when comments panel opens or selected photo changes while panel is open
- Unsubscribes from previous topic
- Forwards PubSub messages to the component via `send_update/2`

## Testing

**Context tests** (`test/ancestry/comments_test.exs`):
- CRUD operations
- Validation: empty text rejected
- Ordering: oldest first
- Cascade: deleting a photo deletes its comments

**LiveComponent tests** (`test/web/live/comments/photo_comments_component_test.exs`):
- Panel renders existing comments
- Form submission creates comment
- Edit flow: click edit, modify, save
- Delete: comment disappears
- Real-time: PubSub broadcast appears

**GalleryLive.Show integration** (`test/web/live/gallery_live/show_test.exs`):
- Toggle button opens/closes panel
- Correct comments load for selected photo
- Photo navigation reloads comments
- Closing lightbox closes panel
