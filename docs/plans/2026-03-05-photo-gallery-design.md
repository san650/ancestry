# Photo Gallery Feature Design

Date: 2026-03-05

## Overview

A shared photo gallery feature for the Family app. All galleries are visible to all users (no auth in scope). Users can create galleries, upload high-resolution photos (including RAW formats), view them in a grid, and browse them in a lightbox.

---

## Data Model

### `Gallery`
- `id`
- `name :string`
- `inserted_at`, `updated_at`

### `Photo`
- `id`
- `gallery_id` (belongs_to Gallery, `on_delete: :delete_all`)
- `image` — Waffle.Ecto attachment field storing all three processed versions
- `original_path :string` — path to the raw uploaded file before processing (e.g. `priv/static/uploads/originals/{uuid}/photo.jpg`)
- `original_filename :string` — original name as provided by the user (used for download prompt only, never in paths)
- `content_type :string`
- `status :string` — `"pending"` | `"processed"` | `"failed"`
- `inserted_at` (ordering: most recent last = `ORDER BY inserted_at ASC`)

### Waffle Uploader (`Family.Uploaders.Photo`)

Three versions generated from the original:
- `:original` — stored as-is
- `:large` — max 1920px wide, aspect ratio preserved
- `:thumbnail` — max 400px wide, aspect ratio preserved

Gallery cascade: deleting a gallery deletes all its photos via DB `ON DELETE CASCADE` and Ecto `on_delete: :delete_all`. Deleting a photo removes all three stored files via Waffle then deletes the DB record.

---

## Storage

**Library:** `waffle` + `waffle_ecto`
**Image processing:** `image` library (libvips wrapper)

Storage backend is config-driven:

```elixir
# Local (dev/prod initial)
config :waffle, storage: Waffle.Storage.Local

# Future cloud
config :waffle, storage: Waffle.Storage.S3
```

Local files are stored under `priv/static/uploads/photos/{gallery_id}/{uuid}/` and served via Phoenix's static file plug. Switching to S3 requires only a config change and credentials — no application code or schema changes.

---

## Upload Flow

### Client side
- Phoenix LiveView `allow_upload/3` with drag & drop support
- Accepted types: `image/jpeg`, `image/png`, `image/webp`, `image/gif`, `image/x-adobe-dng`, `image/x-nikon-nef` (plus extension-based fallback for RAW formats where browsers report `application/octet-stream`)
- Max file size: 300MB per file
- Max concurrent uploads: 10 at a time
- Per-file progress bars shown in a staging list while uploading

### Server side (`consume_uploaded_entries`)
1. Copy binary to `priv/static/uploads/originals/{uuid}/photo.{ext}` (extension derived from content type)
2. Insert `Photo` record with `status: "pending"`, `original_path`, `original_filename`, `content_type`, `gallery_id`
3. Enqueue `Family.Workers.ProcessPhotoJob` with `photo_id`
4. Photo appears immediately in the grid as a pulsing spinner placeholder

### Oban job (`ProcessPhotoJob`)
1. Load photo by id
2. Read file from `original_path`
3. Call Waffle uploader to generate and store `:original`, `:large`, `:thumbnail` versions
4. Update photo: set `image` attachment + `status: "processed"`
5. Broadcast `{:photo_processed, photo}` via `Phoenix.PubSub` on `"gallery:{id}"`

On failure, Oban retries with exponential backoff. After max retries, status is set to `"failed"` and `:photo_failed` is broadcast.

**RAW format note:** libvips supports DNG well; NEF support depends on the host system's libvips build. This must be verified as a deployment requirement. Failed processing shows an error state with Retry and Remove options.

---

## UI/UX

### Gallery list page (`/galleries`)
- Default landing page
- Grid of gallery cards showing name and photo count
- "New Gallery" button opens a **modal** with a name input
- Each card links to the gallery show page
- Galleries can be deleted with a confirmation modal

### Gallery show page (`/galleries/:id`)

**Upload area** (top of page):
- Drag & drop zone + "Select files" button
- Staging list with per-file progress bars appears while uploads are in flight

**Photo grid:**
- Defaults to **masonry layout**; toggle button switches to **uniform grid**
- Pending photos show a pulsing spinner placeholder
- Processed photos show their thumbnail

**Selection mode:**
- "Select" button in toolbar activates selection mode
- Top bar slides in showing: selected photo count, "Delete" button, "Cancel" button
- Tapping a photo toggles its selection (checkmark overlay)
- "Delete" opens a confirmation modal ("Delete N photos? This cannot be undone.")
- Confirming deletes all selected photos and exits selection mode

### Lightbox
- Clicking a thumbnail (outside selection mode) opens a full-screen overlay
- `:large` version centered, aspect ratio preserved, dark background
- Horizontal thumbnail strip at the bottom; current photo highlighted; click any thumbnail to jump to it
- Left/right arrow buttons + `ArrowLeft`/`ArrowRight` keyboard navigation (via `phx-window-keydown`)
- Download button fetches the `:original`
- Escape or click-outside closes it
- State driven by `@selected_photo` assign — no page navigation

---

## Error Handling

- **Upload validation** — type and size enforced client-side by LiveView; invalid entries show inline errors in the staging list
- **Oban failures** — retried with backoff; after max retries photo shows error state with "Retry" (re-enqueues job) and "Remove" (deletes record) options
- **File deletion failures** — if a file is missing from disk during deletion, the error is logged and the DB record is still removed; we don't block the user
- **Concurrent upload cap** — max 10 files at a time enforced by `allow_upload`; UI shows a clear message if exceeded
- **RAW processing failures** — treated as Oban job failures with the same retry/error state flow

---

## Testing

- **Context/schema tests** — gallery and photo changesets, cascade deletes, status transitions
- **Oban job tests** — `ProcessPhotoJob` with a real image fixture: verify three versions written, status becomes `"processed"`, PubSub broadcast fires; corrupt file results in `"failed"` after retries
- **LiveView tests:**
  - Gallery list: create via modal, delete with confirmation
  - Gallery show: upload flow (Oban mocked), selection mode, delete with confirmation, grid layout toggle
  - Lightbox: open, keyboard navigation, thumbnail strip, download link
- **Storage isolation** — Waffle configured to use a temp directory in test env, cleaned up after each test
