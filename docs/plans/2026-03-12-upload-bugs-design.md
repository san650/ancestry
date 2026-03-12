# Upload Bugs Design

Date: 2026-03-12

## Overview

Fix two bugs in the gallery upload feature and reproduce them with e2e tests before fixing.

**Bug 1:** Drag & drop with >10 images only uploads the first batch. Subsequent batches are never fed to the file input.

**Bug 2:** Clicking the "Upload" button and selecting files via the OS file picker does not open the upload modal or complete the upload.

---

## Root Cause Analysis

### Bug 1: Multi-batch drag & drop stops after first batch

In `upload_queue.js`, the flow for drag & drop is:

1. `queueFiles()` stores all files in `this.queue`, pushes `queue_files` event, calls `feedNextBatch()`
2. `feedNextBatch()` splices 10 files from the queue, sets them on the file input, dispatches `change`
3. `auto_upload: true` picks them up and uploads to the server
4. `updated()` watches for all entries to reach 100% progress, then pushes `upload_photos`
5. Server handles `upload_photos`, pushes `batch_complete` back to the hook
6. `batch_complete` handler calls `feedNextBatch()` for the next 10

The likely failure point is in `updated()` — after `batch_complete` fires and `feedNextBatch()` injects the next batch, the LiveView re-renders. The `updated()` callback needs to correctly detect the new batch's entries and their progress. A race condition or stale DOM query may prevent the second batch from ever triggering `upload_photos`.

### Bug 2: Upload button does nothing

The Upload button uses `onclick` to programmatically click the hidden file input. When the user selects files:

1. The `change` event fires on the file input
2. The hook's `change` listener runs (guarded by `if (this.feedingBatch) return`)
3. It sets `this.queue` and `this.currentBatch` from the selected files, pushes `queue_files`
4. It does NOT call `feedNextBatch()` — by design, since LiveView's own `change` handler already has the files

The problem: LiveView's `live_file_input` has its own change handler that starts auto-upload. But the hook's `updated()` callback checks `entries.length !== this.currentBatch.length` — if these don't align (e.g., the user selected fewer than 10 files but `currentBatch` was set differently, or the entry DOM nodes don't exist yet when `updated()` fires), the upload never completes because `upload_photos` is never pushed.

---

## E2E Test Strategy

Write e2e tests that reproduce each bug BEFORE fixing. Tests go in the existing `test/web/e2e/gallery_upload_test.exs`.

### Bug 1 test: Multi-batch drag & drop

- Create a gallery
- Visit the gallery page
- Synthesize a drop event with 12+ small image files (use minimal JPEG bytes)
- Assert the upload modal appears
- Wait for all photos to appear in the gallery stream (not just the first 10)

### Bug 2 test: Upload button file picker

- Create a gallery
- Visit the gallery page
- Use the `upload_image` helper to set files on the file input and dispatch `change`
- Assert the upload modal appears
- Assert photos appear in the gallery stream

### Existing tests

The file already has skeleton tests for these scenarios. They need to be updated to:
- Use realistic file counts for Bug 1 (>10 files to trigger multi-batch)
- Add appropriate waits for async processing (Oban jobs, PubSub broadcasts)
- Assert on the correct DOM elements

---

## Fix Strategy

Both bugs are in `assets/js/upload_queue.js`. The fixes involve:

1. **Bug 2 fix:** Ensure the `change` handler (file picker path) correctly sets `this.currentBatch` to match what LiveView will see as entries, so `updated()` can detect completion and push `upload_photos`.

2. **Bug 1 fix:** Ensure `feedNextBatch()` after `batch_complete` correctly transitions to the next batch, and `updated()` can detect the new entries. May need to handle the DOM update timing — `feedNextBatch()` is called synchronously from the `batch_complete` handler, but the new entries won't appear in the DOM until the next LiveView render cycle.

Server-side changes in `show.ex` may also be needed if the `upload_photos` handler doesn't correctly handle the queue state across multiple batches.
