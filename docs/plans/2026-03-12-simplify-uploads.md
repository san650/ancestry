# Simplify Image Uploads Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the custom batch upload queue with standard LiveView uploads, keeping drag & drop and the upload modal UX.

**Architecture:** Remove the external `UploadQueue` JS hook and all batch/queue server-side state. Use LiveView's built-in `@uploads.photos.entries` for progress tracking, a colocated `.DragDrop` hook for drag & drop, and a small `@upload_results` assign for the done screen.

**Tech Stack:** Phoenix LiveView (uploads, streams, colocated hooks), Oban (background processing)

---

### Task 1: Update LiveView tests for the new upload modal

The existing upload modal tests reference removed events (`queue_files`, `cancel_upload_modal`, `confirm_cancel_upload`). Replace them with tests for the simplified flow.

**Files:**
- Modify: `test/web/live/gallery_live/show_test.exs`

**Step 1: Replace the upload modal test block**

Remove the entire `describe "upload modal"` block and replace with:

```elixir
describe "upload modal" do
  test "uploading a file opens the modal and shows progress", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

    refute has_element?(view, "#upload-modal")

    # Simulate uploading a file via LiveView test helpers
    file_input(view, "#upload-form", :photos, [
      %{
        name: "photo1.jpg",
        content: File.read!("test/fixtures/test_image.jpg"),
        type: "image/jpeg"
      }
    ])

    # Modal should open showing progress
    assert has_element?(view, "#upload-modal")
  end

  test "close_upload_modal closes the modal", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

    # Upload a file to open modal
    file_input(view, "#upload-form", :photos, [
      %{
        name: "photo1.jpg",
        content: File.read!("test/fixtures/test_image.jpg"),
        type: "image/jpeg"
      }
    ])

    assert has_element?(view, "#upload-modal")

    view |> element("#upload-modal-close") |> render_click()

    refute has_element?(view, "#upload-modal")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/web/live/gallery_live/show_test.exs`
Expected: FAIL — the new modal behaviour doesn't exist yet

**Step 3: Commit**

```
git add test/web/live/gallery_live/show_test.exs
git commit -m "Update upload modal tests for simplified upload flow"
```

---

### Task 2: Simplify LiveView assigns and remove batch events

Strip out all batch/queue assigns and events from the Show LiveView.

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex`

**Step 1: Replace mount assigns**

In `mount/3`, remove these assigns:
- `assign(:upload_modal, nil)`
- `assign(:upload_queue, [])`
- `assign(:upload_cancel_confirm, false)`

Add these assigns:
- `assign(:show_upload_modal, false)`
- `assign(:upload_results, [])`

**Step 2: Update `allow_upload` config**

Change `max_entries: 10` to `max_entries: 50`.

**Step 3: Simplify `handle_progress/3`**

Replace the existing `handle_progress/3` with:

```elixir
defp handle_progress(:photos, _entry, socket) do
  entries = socket.assigns.uploads.photos.entries
  all_done? = entries != [] and Enum.all?(entries, & &1.done?)

  socket =
    if not socket.assigns.show_upload_modal and entries != [] do
      assign(socket, :show_upload_modal, true)
    else
      socket
    end

  if all_done? do
    process_uploads(socket)
  else
    {:noreply, socket}
  end
end
```

**Step 4: Remove batch events**

Delete these `handle_event` clauses entirely:
- `"queue_files"`
- `"cancel_upload_modal"`
- `"confirm_cancel_upload"`
- `"dismiss_cancel_confirm"`
- `"cancel_upload"`

**Step 5: Simplify `close_upload_modal` event**

Replace with:

```elixir
def handle_event("close_upload_modal", _, socket) do
  {:noreply,
   socket
   |> assign(:show_upload_modal, false)
   |> assign(:upload_results, [])}
end
```

**Step 6: Simplify `process_uploads/1`**

Replace the entire function with:

```elixir
defp process_uploads(socket) do
  gallery = socket.assigns.gallery

  results =
    consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
      uuid = Ecto.UUID.generate()
      ext = ext_from_content_type(entry.client_type)
      dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
      File.mkdir_p!(dest_dir)
      dest_path = Path.join(dest_dir, "photo#{ext}")
      File.cp!(tmp_path, dest_path)

      case Galleries.create_photo(%{
             gallery_id: gallery.id,
             original_path: dest_path,
             original_filename: entry.client_name,
             content_type: entry.client_type
           }) do
        {:ok, photo} -> {:ok, {:ok, photo}}
        {:error, _} -> {:ok, {:error, entry.client_name}}
      end
    end)

  {uploaded, errored} =
    Enum.split_with(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)

  uploaded_photos = Enum.map(uploaded, fn {:ok, photo} -> photo end)

  upload_results =
    Enum.map(uploaded_photos, fn photo ->
      %{name: photo.original_filename, status: :ok}
    end) ++
      Enum.map(errored, fn {:error, name} ->
        %{name: name, status: :error, error: "Upload failed"}
      end)

  socket =
    socket
    |> assign(:upload_results, upload_results)
    |> assign(:show_upload_modal, true)

  socket = Enum.reduce(uploaded_photos, socket, &stream_insert(&2, :photos, &1))
  {:noreply, socket}
end
```

**Step 7: Run tests**

Run: `mix test test/web/live/gallery_live/show_test.exs`
Expected: Some tests pass, template tests may fail (template not updated yet)

**Step 8: Commit**

```
git add lib/web/live/gallery_live/show.ex
git commit -m "Simplify LiveView assigns and remove batch upload events"
```

---

### Task 3: Update the upload modal template

Replace the batch queue modal with a simpler modal driven by `@uploads.photos.entries` and `@upload_results`.

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex`

**Step 1: Replace the upload modal section**

Replace everything between `<%!-- Upload progress modal --%>` and the closing `<% end %>` (lines 169-322) with:

```heex
<%!-- Upload progress modal --%>
<%= if @show_upload_modal do %>
  <div
    id="upload-modal"
    class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4"
  >
    <div class="absolute inset-0 bg-black/60 backdrop-blur-sm"></div>
    <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-lg flex flex-col max-h-[80vh]">
      <%!-- Modal header --%>
      <div class="flex items-center justify-between px-6 py-4 border-b border-base-200 shrink-0">
        <%= if @upload_results != [] do %>
          <h2 class="text-lg font-semibold text-base-content">
            <%= if Enum.any?(@upload_results, &(&1.status == :error)) do %>
              Upload complete with errors
            <% else %>
              Upload complete
            <% end %>
          </h2>
        <% else %>
          <% done_count = Enum.count(@uploads.photos.entries, & &1.done?) %>
          <% total_count = length(@uploads.photos.entries) %>
          <h2 class="text-lg font-semibold text-base-content">
            Uploading photos ({done_count} of {total_count})
          </h2>
        <% end %>
        <%= if @upload_results != [] do %>
          <button
            id="upload-modal-close"
            phx-click="close_upload_modal"
            class="p-1.5 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        <% end %>
      </div>

      <%!-- File list --%>
      <div class="overflow-y-auto flex-1 px-6 py-4 space-y-2">
        <%= if @upload_results != [] do %>
          <%!-- Done state: show results --%>
          <%= for file <- Enum.filter(@upload_results, &(&1.status == :error)) do %>
            <div class="flex items-center gap-3 bg-error/5 border border-error/20 rounded-xl px-4 py-3">
              <.icon name="hero-x-circle" class="w-5 h-5 text-error shrink-0" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">{file.name}</p>
                <p class="text-xs text-error mt-0.5">{file[:error] || "Upload failed"}</p>
              </div>
            </div>
          <% end %>
          <%= for file <- Enum.filter(@upload_results, &(&1.status == :ok)) do %>
            <div class="flex items-center gap-3 bg-success/5 border border-success/20 rounded-xl px-4 py-3">
              <.icon name="hero-check-circle" class="w-5 h-5 text-success shrink-0" />
              <p class="text-sm font-medium text-base-content truncate flex-1">{file.name}</p>
            </div>
          <% end %>
        <% else %>
          <%!-- Uploading state: show progress --%>
          <%= for entry <- @uploads.photos.entries do %>
            <div class="flex items-center gap-3 bg-base-100 rounded-xl border border-base-200 px-4 py-3">
              <%= cond do %>
                <% entry.done? -> %>
                  <.icon name="hero-check-circle" class="w-5 h-5 text-success shrink-0" />
                  <p class="text-sm font-medium text-base-content truncate flex-1">
                    {entry.client_name}
                  </p>
                <% upload_errors(@uploads.photos, entry) != [] -> %>
                  <.icon name="hero-x-circle" class="w-5 h-5 text-error shrink-0" />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content truncate">
                      {entry.client_name}
                    </p>
                    <%= for err <- upload_errors(@uploads.photos, entry) do %>
                      <p class="text-xs text-error mt-1">{upload_error_to_string(err)}</p>
                    <% end %>
                  </div>
                <% true -> %>
                  <.icon name="hero-arrow-up-tray" class="w-5 h-5 text-primary shrink-0" />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content truncate">
                      {entry.client_name}
                    </p>
                    <div class="mt-1.5 h-1.5 bg-base-200 rounded-full overflow-hidden">
                      <div
                        class="h-full bg-primary rounded-full transition-all duration-300"
                        style={"width: #{entry.progress}%"}
                      >
                      </div>
                    </div>
                  </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Modal footer --%>
      <div class="px-6 py-4 border-t border-base-200 shrink-0">
        <%= if @upload_results != [] do %>
          <button
            phx-click="close_upload_modal"
            class="w-full px-4 py-2 bg-primary text-primary-content rounded-xl font-medium hover:bg-primary/90 transition-colors"
          >
            Done
          </button>
        <% else %>
          <div class="text-center text-sm text-base-content/40">
            Uploading...
          </div>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

**Step 2: Run tests**

Run: `mix test test/web/live/gallery_live/show_test.exs`
Expected: All tests pass

**Step 3: Commit**

```
git add lib/web/live/gallery_live/show.html.heex
git commit -m "Replace batch queue modal with simplified upload modal template"
```

---

### Task 4: Replace external JS hook with colocated `.DragDrop` hook

**Files:**
- Delete: `assets/js/upload_queue.js`
- Modify: `assets/js/app.js`
- Modify: `lib/web/live/gallery_live/show.html.heex`

**Step 1: Remove `UploadQueue` from `app.js`**

Delete the import line:
```js
import UploadQueue from "./upload_queue"
```

Remove `UploadQueue` from the hooks object so it reads:
```js
hooks: {...colocatedHooks},
```

**Step 2: Delete `assets/js/upload_queue.js`**

**Step 3: Update the template**

Change the `#gallery-show-root` div from:
```heex
<div
  id="gallery-show-root"
  phx-hook="UploadQueue"
  class="max-w-7xl mx-auto"
>
```

To:
```heex
<div
  id="gallery-show-root"
  phx-hook=".DragDrop"
  class="max-w-7xl mx-auto"
>
```

**Step 4: Add the colocated hook script**

Add this right after the `#gallery-show-root` closing `</div>` tag (before the upload modal):

```heex
<script :type={Phoenix.LiveView.ColocatedHook} name=".DragDrop">
  export default {
    mounted() {
      this.dragCounter = 0
      this.fileInput = document.querySelector('#upload-form [type=file]')

      this._onDragEnter = (e) => {
        e.preventDefault()
        this.dragCounter++
        if (this.dragCounter === 1) {
          const count = e.dataTransfer?.items?.length || 0
          const overlay = document.getElementById("drag-overlay")
          if (!overlay) return
          const label = overlay.querySelector("[data-drag-count]")
          if (label) {
            label.textContent = `Drop to upload ${count} photo${count !== 1 ? "s" : ""}`
          }
          overlay.classList.remove("hidden")
        }
      }

      this._onDragLeave = (e) => {
        e.preventDefault()
        this.dragCounter--
        if (this.dragCounter === 0) {
          const overlay = document.getElementById("drag-overlay")
          if (overlay) overlay.classList.add("hidden")
        }
      }

      this._onDragOver = (e) => { e.preventDefault() }

      this._onDrop = (e) => {
        e.preventDefault()
        this.dragCounter = 0
        const overlay = document.getElementById("drag-overlay")
        if (overlay) overlay.classList.add("hidden")

        const files = Array.from(e.dataTransfer.files).filter(
          (f) => f.type.startsWith("image/") || f.name.match(/\.(dng|nef|tiff?|raw)$/i)
        )
        if (files.length === 0) return

        const dt = new DataTransfer()
        files.forEach((f) => dt.items.add(f))
        this.fileInput.files = dt.files
        this.fileInput.dispatchEvent(new Event("change", { bubbles: true }))
      }

      document.addEventListener("dragenter", this._onDragEnter)
      document.addEventListener("dragleave", this._onDragLeave)
      document.addEventListener("dragover", this._onDragOver)
      document.addEventListener("drop", this._onDrop)
    },

    destroyed() {
      document.removeEventListener("dragenter", this._onDragEnter)
      document.removeEventListener("dragleave", this._onDragLeave)
      document.removeEventListener("dragover", this._onDragOver)
      document.removeEventListener("drop", this._onDrop)
    }
  }
</script>
```

**Step 5: Run tests**

Run: `mix test test/web/live/gallery_live/show_test.exs`
Expected: All tests pass

**Step 6: Commit**

```
git add -A
git commit -m "Replace external UploadQueue hook with colocated .DragDrop hook"
```

---

### Task 5: Update E2E tests

The E2E tests reference the old batch queue behavior. Update them for the simplified flow.

**Files:**
- Modify: `test/web/e2e/gallery_upload_test.exs`

**Step 1: Update the drag & drop test**

The "drag and drop uploads multiple batches of photos" test should be simplified. There are no more batches — just a single set of files. Reduce to a reasonable number (e.g. 5 files instead of 12 to keep tests fast) and update the description:

```elixir
test "drag and drop uploads multiple photos", %{
  conn: conn,
  gallery: gallery
} do
  conn
  |> visit(~p"/galleries/#{gallery.id}")
  |> wait_liveview()
  |> evaluate("""
    (function() {
      const minJpeg = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9]);
      const dt = new DataTransfer();
      for (let i = 1; i <= 5; i++) {
        dt.items.add(new File([minJpeg], `photo_${i}.jpg`, {type: 'image/jpeg'}));
      }
      document.body.dispatchEvent(
        new DragEvent('drop', {dataTransfer: dt, bubbles: true, cancelable: true})
      );
    })();
  """)
  |> assert_has("#upload-modal", timeout: 5_000)
  |> assert_has("#photo-grid [id^='photos-'][data-phx-stream]",
    count: 5,
    timeout: 30_000
  )
end
```

**Step 2: Run E2E tests**

Run: `mix test test/web/e2e/gallery_upload_test.exs`
Expected: All E2E tests pass

**Step 3: Commit**

```
git add test/web/e2e/gallery_upload_test.exs
git commit -m "Update E2E tests for simplified upload flow"
```

---

### Task 6: Run precommit and verify

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Clean compile (no warnings), formatted, all tests pass

**Step 2: Fix any issues**

If there are warnings or test failures, fix them.

**Step 3: Final commit (if needed)**

```
git add -A
git commit -m "Fix precommit issues"
```
