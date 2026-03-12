# Upload Bugs Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix two upload bugs (multi-batch drag & drop stops after first batch; Upload button does nothing) with e2e test reproduction first.

**Architecture:** Both bugs live in `assets/js/upload_queue.js`. The JS hook manages file queuing, batching, and coordination with LiveView's auto-upload. E2E tests use `phoenix_test_playwright` to drive a real browser and verify the full upload flow including JS hooks.

**Tech Stack:** Phoenix LiveView, PhoenixTest.Playwright, JavaScript (DataTransfer API)

---

### Task 1: E2E test — Upload button file picker (Bug 2 reproduction)

**Files:**
- Modify: `test/web/e2e/gallery_upload_test.exs` (the existing "upload button opens progress modal" test)

**Step 1: Update the test to reproduce Bug 2**

The existing test uses `upload_image` which sets files and dispatches `change`. It asserts on `#upload-modal` and a photo in the stream. This should already fail if the bug exists. However, the photo won't appear until the Oban job processes it (status goes from "pending" to "processed"), but stream_insert happens immediately in `upload_photos` with status "pending". So asserting on `[id^='photos-']` should work even without Oban.

Replace the existing test:

```elixir
test "upload button opens progress modal and adds photo to gallery", %{
  conn: conn,
  gallery: gallery
} do
  conn
  |> visit(~p"/galleries/#{gallery.id}")
  |> wait_liveview()
  |> upload_image("#upload-form [type=file]", ["test/fixtures/test_image.jpg"])
  |> assert_has("#upload-modal", timeout: 5_000)
  |> assert_has("#photo-grid [id^='photos-'][data-phx-stream]", timeout: 10_000)
end
```

The key addition is `:timeout` on both assertions — the upload flow is async (auto_upload + server processing + DOM update) so we need to poll.

**Step 2: Run the test to verify it fails (reproduces Bug 2)**

Run: `mix test test/web/e2e/gallery_upload_test.exs --only e2e -t e2e --seed 0 2>&1 | tail -30`

Expected: FAIL — the modal never appears and/or no photo appears in the grid.

**Step 3: Commit**

```
git add test/web/e2e/gallery_upload_test.exs
git commit -m "Add e2e test reproducing upload button bug"
```

---

### Task 2: E2E test — Multi-batch drag & drop (Bug 1 reproduction)

**Files:**
- Modify: `test/web/e2e/gallery_upload_test.exs`

**Step 1: Update the drag & drop test to use >10 files**

Replace the existing "drag and drop opens progress modal" test. We need to drop 12 files to trigger two batches (10 + 2). Use minimal JPEG byte sequences as synthetic files.

```elixir
test "drag and drop uploads multiple batches of photos", %{
  conn: conn,
  gallery: gallery
} do
  # Drop 12 files to trigger 2 batches (10 + 2)
  conn
  |> visit(~p"/galleries/#{gallery.id}")
  |> wait_liveview()
  |> evaluate("""
    (function() {
      const minJpeg = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9]);
      const dt = new DataTransfer();
      for (let i = 1; i <= 12; i++) {
        dt.items.add(new File([minJpeg], `photo_${i}.jpg`, {type: 'image/jpeg'}));
      }
      document.dispatchEvent(new DragEvent('drop', {dataTransfer: dt, bubbles: true, cancelable: true}));
    })();
  """)
  |> assert_has("#upload-modal", timeout: 5_000)
  |> assert_has("#photo-grid [id^='photos-'][data-phx-stream]", count: 12, timeout: 30_000)
end
```

Note: we dispatch `drop` on `document` (not `#gallery-show-root`) since the hook attaches drag listeners to `document`.

**Step 2: Run the test to verify it fails (reproduces Bug 1)**

Run: `mix test test/web/e2e/gallery_upload_test.exs --only e2e -t e2e --seed 0 2>&1 | tail -30`

Expected: FAIL — only 10 photos appear, the remaining 2 are never uploaded.

**Step 3: Commit**

```
git add test/web/e2e/gallery_upload_test.exs
git commit -m "Add e2e test reproducing multi-batch drag & drop bug"
```

---

### Task 3: Fix Bug 2 — Upload button change handler

**Files:**
- Modify: `assets/js/upload_queue.js`

**Step 1: Diagnose the bug**

In the `change` handler (lines 17-29), when the user picks files via the OS file picker:
1. `this.queue` is set to all files, then `this.queue.splice(0, 10)` sets `this.currentBatch`
2. `pushEvent("queue_files", ...)` notifies the server to open the modal
3. LiveView's own `live_file_input` change handler fires and starts auto-upload
4. But `upload_photos` is never pushed because `updated()` can't detect completion

The issue: LiveView's auto-upload fires, but `updated()` checks `this.currentBatch.length === 0` and bails. Actually looking more carefully — `this.currentBatch` IS set on line 23. The real issue may be that `this.queue` is set to ALL files (line 22: `this.queue = [...files]`) and then immediately spliced (line 23: `this.currentBatch = this.queue.splice(0, 10)`). But the native file picker already gave ALL selected files to LiveView via its own change handler. So if the user selected 3 files, LiveView has 3 entries, but `this.currentBatch` has 3 files (splice of min(10, 3)). That should match.

The more likely issue: the `change` event fires on the file input, but LiveView's `live_file_input` hook processes it first. By the time our hook's `updated()` fires, the entries may not yet have `data-upload-entry` attributes in the DOM, or the entries haven't reached 100% progress yet.

Actually, re-reading the code: the `updated()` callback runs on the `#gallery-show-root` element (where `phx-hook="UploadQueue"` is). But the upload entries (`[data-upload-entry]`) are inside `#upload-modal`, which is OUTSIDE `#gallery-show-root` in the template. The `updated()` hook only fires when the hook's element or its children change. Since `#upload-modal` is a sibling (rendered after `#gallery-show-root` closes), `updated()` may never fire when upload progress changes.

Wait — actually looking at the template again: `#gallery-show-root` closes at line 167, and `#upload-modal` starts at line 170. They are siblings inside `<Layouts.app>`. So `updated()` on `#gallery-show-root` does NOT fire when `#upload-modal` content changes.

But `updated()` fires whenever LiveView re-renders the hook's element. Since `@uploads.photos.entries` change triggers a re-render of the form inside `#gallery-show-root` (the hidden upload form at line 54), the `updated()` callback SHOULD fire.

Let me re-examine: the hidden form `<form id="upload-form">` with `<.live_file_input>` is at lines 54-56, which is OUTSIDE `#gallery-show-root` (it's a sibling before it). So upload entry changes re-render `#upload-form`, not `#gallery-show-root`.

**This is the root cause for both bugs.** The `updated()` callback on `#gallery-show-root` never fires when upload progress changes, because the upload form and modal are siblings, not children.

**Step 2: Fix — Move the hook or use a different detection mechanism**

The simplest fix: move `phx-hook="UploadQueue"` to a wrapper element that contains both the upload form and the modal. Or, use `handleEvent` from the server to detect batch completion instead of polling the DOM in `updated()`.

Better approach: instead of relying on `updated()` to detect when all entries hit 100%, use LiveView's built-in `progress` callback. Actually, the simplest fix is to move the hook to a parent element that wraps everything, or to stop using `updated()` and instead have the server detect upload completion.

The server already knows when auto-upload completes — it triggers `upload_photos` via `phx-submit` on the form. But wait, the form has `phx-submit="upload_photos"` but auto_upload doesn't auto-submit. The `updated()` hook was the mechanism to trigger submission.

**Best fix: Move phx-hook="UploadQueue" to a wrapper div that contains the upload form, gallery, and modal.** This way `updated()` fires on any re-render of the upload entries.

In `show.html.heex`, wrap the upload form + gallery root + modal in a single div with the hook:

```heex
<div id="upload-hook-root" phx-hook="UploadQueue">
  <%!-- Hidden form --%>
  <form id="upload-form" phx-change="validate" phx-submit="upload_photos" class="hidden">
    <.live_file_input upload={@uploads.photos} />
  </form>

  <%!-- Drag overlay --%>
  ...

  <div id="gallery-show-root" class="max-w-7xl mx-auto">
    ...gallery content (remove phx-hook="UploadQueue" from here)...
  </div>

  <%!-- Upload modal --%>
  ...
</div>
```

And in `upload_queue.js`, update the `fileInput` selector since we're now on the parent:

```javascript
this.fileInput = this.el.querySelector('#upload-form [type=file]')
```

Wait — actually `this.el` would be the hook element. Since `fileInput` is found with `document.querySelector`, it works regardless. But using `this.el.querySelector` is cleaner.

Similarly, update the `updated()` entry query to scope to our element:

```javascript
const entries = this.el.querySelectorAll("[data-upload-entry]")
```

**Step 3: Apply the template fix**

In `show.html.heex`:
- Add `<div id="upload-hook-root" phx-hook="UploadQueue">` before the upload form (line 53)
- Remove `phx-hook="UploadQueue"` from `#gallery-show-root` (line 73)
- Close the wrapper `</div>` after the upload modal (after line 322, before lightbox)

**Step 4: Apply the JS fix**

In `upload_queue.js`, change line 9:
```javascript
// Before:
this.fileInput = document.querySelector('#upload-form [type=file]')

// After:
this.fileInput = this.el.querySelector('#upload-form [type=file]')
```

Change line 90:
```javascript
// Before:
const entries = document.querySelectorAll("[data-upload-entry]")

// After:
const entries = this.el.querySelectorAll("[data-upload-entry]")
```

**Step 5: Run Bug 2 e2e test**

Run: `mix test test/web/e2e/gallery_upload_test.exs --only e2e -t e2e --seed 0 2>&1 | tail -30`

Expected: The "upload button opens progress modal" test now PASSES.

**Step 6: Commit**

```
git add lib/web/live/gallery_live/show.html.heex assets/js/upload_queue.js
git commit -m "Fix upload button by moving hook to wrapper element"
```

---

### Task 4: Fix Bug 1 — Multi-batch drag & drop continuation

**Files:**
- Modify: `assets/js/upload_queue.js` (possibly)
- Modify: `lib/web/live/gallery_live/show.ex` (possibly)

**Step 1: Verify if Task 3's fix also resolves Bug 1**

Run the multi-batch test from Task 2. The hook relocation may have fixed the `updated()` detection for subsequent batches too.

Run: `mix test test/web/e2e/gallery_upload_test.exs --only e2e -t e2e --seed 0 2>&1 | tail -30`

If the multi-batch test passes, skip to Step 4 (commit). If not, continue.

**Step 2: Debug the batch transition**

If `updated()` now fires correctly but multi-batch still fails, the issue is likely in the batch transition logic. After `batch_complete`:

1. `feedNextBatch()` splices next 10 from `this.queue`
2. Sets `this.fileInput.files` and dispatches `change`
3. The `change` handler has `if (this.feedingBatch) return` guard — good, it won't re-queue
4. LiveView processes the new files, re-renders entries
5. `updated()` should detect the new batch

Potential issue: after `consume_uploaded_entries` in `upload_photos`, LiveView clears all entries. When `feedNextBatch()` adds new files, `updated()` might fire before the new entries appear (entries.length === 0 !== currentBatch.length), so it skips. Then when entries do appear, `updated()` fires again and should work.

If the issue persists, add a small delay or use `requestAnimationFrame` in `feedNextBatch()` after `batch_complete`:

```javascript
this.handleEvent("batch_complete", () => {
  this.awaitingBatchComplete = false
  // Let LiveView finish clearing old entries before feeding new batch
  requestAnimationFrame(() => this.feedNextBatch())
})
```

**Step 3: Run multi-batch test again**

Run: `mix test test/web/e2e/gallery_upload_test.exs --only e2e -t e2e --seed 0 2>&1 | tail -30`

Expected: PASS — all 12 photos appear.

**Step 4: Commit**

```
git add assets/js/upload_queue.js
git commit -m "Fix multi-batch drag & drop upload continuation"
```

---

### Task 5: Run full test suite and precommit

**Step 1: Run the e2e upload tests to confirm both bugs are fixed**

Run: `mix test test/web/e2e/gallery_upload_test.exs --seed 0 2>&1 | tail -30`

Expected: All tests PASS.

**Step 2: Run the full e2e suite**

Run: `mix test test/web/e2e/ --seed 0 2>&1 | tail -30`

Expected: All e2e tests PASS (including the existing navigation test).

**Step 3: Run precommit**

Run: `mix precommit`

Expected: Compilation clean, formatted, all tests pass.

**Step 4: Final commit if any formatting changes**

```
git add -A
git commit -m "Fix formatting from precommit"
```
