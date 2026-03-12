# Simplify Image Upload Functionality

**Date:** 2026-03-12

## Goal

Remove the custom batch upload queue and replace it with standard LiveView upload functionality. Keep drag & drop and the Upload button with modal UX.

## Changes

### LiveView assigns

**Remove:** `@upload_modal`, `@upload_queue`, `@upload_cancel_confirm`

**Add:**
- `@show_upload_modal` (boolean) — toggled by Upload button / drag & drop / close
- `@upload_results` (list of `%{name, status}`) — populated after `consume_uploaded_entries`, shown on the done screen

Upload config: `max_entries: 50`, `auto_upload: true` kept.

Modal state (uploading vs done, errors) derived from `@uploads.photos.entries` during upload, and from `@upload_results` after consumption.

### Upload flow — events

**Keep:**
- `validate` (no-op, required by LiveView)
- `upload_photos` / form submit — `consume_uploaded_entries`, create photos + Oban jobs, stream-insert
- `close_upload_modal` — resets `@show_upload_modal` and `@upload_results`

**Remove:**
- `queue_files`, `cancel_upload_modal`, `confirm_cancel_upload`, `dismiss_cancel_confirm`, `cancel_upload`
- `batch_complete` / `reset_queue` push events
- `@upload_queue` tracking logic in `process_uploads/1`

**Simplified `process_uploads/1`:**
- `consume_uploaded_entries` copies files, creates DB records, enqueues Oban jobs
- Stream-inserts each new photo
- Populates `@upload_results` with success/error per file

**`handle_progress/3`:** checks `Enum.all?(entries, & &1.done?)`, calls `process_uploads/1` when true and opens modal if not already open.

### JS hook — colocated `.DragDrop`

**Delete:** `assets/js/upload_queue.js`

**Remove from `app.js`:** `UploadQueue` import and hook registration.

**Colocated hook `.DragDrop`** on `#gallery-show-root`:
1. `dragenter` / `dragleave` / `dragover` on `document` — show/hide drag overlay with file count
2. `drop` on `document` — filter image files, set on `live_file_input` via `DataTransfer`, dispatch change
3. Cleanup in `destroyed()`

No batch queue, no `pushEvent`, no `handleEvent`. Only bridges drag & drop to the native file input.

Upload button: unchanged (`onclick` triggers file input click directly).

### Modal template

**Uploading state** (`@show_upload_modal && @upload_results == []`):
- Header: "Uploading photos (X of Y)" from entries progress
- File list: `@uploads.photos.entries` with filename + progress bar + per-entry errors
- Footer: no close button

**Done state** (`@upload_results != []`):
- Header: "Upload complete" or "Upload complete with errors"
- File list: `@upload_results` — green check for success, red X with error for failures
- Footer: "Done" button → `close_upload_modal`

**Drag overlay:** unchanged.
