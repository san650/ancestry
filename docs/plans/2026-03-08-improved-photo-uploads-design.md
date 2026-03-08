# Improved Photo Uploads Design

Date: 2026-03-08

## Overview

Overhaul the photo upload UX in the gallery show page. Replace the dedicated upload drop zone with a full-gallery drag & drop surface, move the upload trigger to the top bar, and add an upload progress modal that tracks all files across batched uploads. Photos appear in the gallery immediately as "Processing" placeholders while Oban jobs generate thumbnails in the background.

---

## Architecture & Data Flow

A JS hook (`UploadQueue`) owns the client-side file queue and bridges the user's file selection with LiveView's upload mechanism.

1. User clicks "Upload" in the top bar (triggers hidden `<input type="file" multiple>`) or drops files anywhere on the gallery surface
2. The hook captures all selected `File` objects into its internal queue and notifies the server (`push_event("queue_files", {files: [{name, size}, ...]})`)
3. The server opens the upload modal and populates `@upload_queue` (all files shown as pending)
4. The hook feeds the first batch of 10 files to LiveView's upload input via the `DataTransfer` API, dispatching a synthetic `change` event
5. LiveView uploads the batch in the background; the template shows per-file progress via `@uploads.photos.entries`
6. When all 10 are transferred, the `upload_photos` event fires (same as today), and the server calls `push_event("batch_complete", %{})` back to the hook
7. The hook feeds the next 10 files — repeat until the queue is empty
8. Server marks the modal state as `:done`, showing errors and successfully uploaded previews

`allow_upload` stays at `max_entries: 10` (one batch at a time). animate.css is imported via `app.css`.

---

## Drag & Drop Overlay

- The entire `<div id="gallery">` is the drop target (`phx-drop-target={@uploads.photos.ref}`)
- The `UploadQueue` hook listens for `dragenter`/`dragleave`/`drop` on this element
- On `dragenter`: a full-screen overlay appears (CSS class toggled client-side, no server roundtrip) with a dashed border, dark semi-transparent background, and centered text: "Drop to upload X photos" — X read from `dataTransfer.items.length`
- On `dragleave` (leaving the window) or `drop`: overlay hides immediately

---

## Upload Progress Modal

Opens as soon as the user selects or drops files. Two phases:

### While uploading (`status: :uploading`)

- Header: "Uploading photos (12 of 50)"
- Scrollable file list — each row shows filename, file size, and status:
  - Completed files: green checkmark + 100%
  - Current batch: animated progress bar driven by `entry.progress`
  - Pending (queued): grey "Waiting…" state
  - Errors: red × with a short reason (e.g. "File too large")
- "Cancel" button — clicking shows inline confirmation: "X files haven't uploaded yet. Cancel anyway?" with "Yes, cancel" and "Keep uploading" options
- Canceling stops the JS queue and calls `cancel_upload` for in-flight entries

### After all files transferred (`status: :done`)

- Header: "Upload complete" (or "Upload complete with errors" if any failed)
- Errors section at top (if any): red-tinted rows listing failed files and reasons
- Success section below: small thumbnail grid using browser-side previews via `URL.createObjectURL` (server thumbnails not ready yet)
- "Done" button — closes the modal; new photos appear in the gallery as "Processing" placeholders

---

## Gallery Surface & Processing Placeholders

### Top bar

- "Upload" button added alongside existing layout toggle and select-mode buttons
- Clicking triggers `document.getElementById("photo-file-input").click()` via the hook
- Hidden `<input type="file" multiple accept="...">` placed in the DOM but visually hidden

### Processing placeholders

- When `upload_photos` fires, pending photos are `stream_insert`-ed immediately
- Pending photo cards render:
  - Muted grey background
  - Small image icon
  - "Processing" text
  - `class="animate__animated animate__pulse animate__infinite"` for a gentle pulsing effect (animate.css)
- When `{:photo_processed, photo}` arrives via PubSub, `stream_insert` replaces the placeholder with the real thumbnail
- Failed photos (`status: "failed"`) show a red-tinted placeholder with an × icon and "Failed" text

---

## Error Handling

- **File type / size errors:** Caught by LiveView's `allow_upload` validation; shown immediately as red rows in the modal
- **Mid-upload network errors:** LiveView surfaces as entry errors; hook marks those files failed in the modal and continues with the next batch
- **Non-image files dragged in:** Invalid files added to queue and shown as errors immediately in the modal
- **Cancel mid-upload:** Hook drains the queue; in-flight entries cancelled via `cancel_upload`; server resets modal state

---

## Testing

- **Batching logic:** LiveView integration tests — queue of 25 files triggers 3 batches (10/10/5), `batch_complete` advances queue
- **Modal states:** Assert modal opens on file selection, transitions to `:done`, and closes correctly
- **Processing placeholders:** Test that pending photos render placeholder, then `stream_insert` updates to thumbnail on PubSub broadcast
- **Cancel flow:** Assert in-flight entries are cancelled and queue cleared on user confirmation
- **animate.css:** Assert pending photo elements have the animate.css classes in rendered HTML
- **Drag & drop overlay:** Manual/visual testing (browser `dragenter` events not testable in LiveView integration tests)
