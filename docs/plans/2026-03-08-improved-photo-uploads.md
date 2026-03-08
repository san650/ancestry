# Improved Photo Uploads Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the dedicated upload zone with a full-gallery drag & drop surface, add a batched upload progress modal, and show animated "Processing" placeholders while Oban jobs generate thumbnails.

**Architecture:** A JS hook (`UploadQueue`) manages a client-side file queue, feeding batches of 10 files at a time to LiveView's upload mechanism via the `DataTransfer` API. `auto_upload: true` starts transfers immediately on file selection. The hook's `updated()` callback detects when all entries in a batch reach 100% and pushes `upload_photos` to the server, which consumes the entries and signals `batch_complete` to advance the queue.

**Tech Stack:** Phoenix LiveView (auto_upload), Elixir/Oban (background processing), animate.css (processing placeholder animations), Tailwind CSS

---

### Task 1: Install animate.css

**Files:**
- Create: `assets/vendor/animate.css`
- Modify: `assets/css/app.css`

**Step 1: Download animate.css to vendor**

```bash
curl -sL "https://cdnjs.cloudflare.com/ajax/libs/animate.css/4.1.1/animate.min.css" \
  -o assets/vendor/animate.css
```

**Step 2: Verify the file downloaded correctly**

```bash
head -3 assets/vendor/animate.css
```

Expected: starts with `/*!` comment header for animate.css 4.1.1.

**Step 3: Import animate.css in app.css**

In `assets/css/app.css`, add this line after the `@plugin` blocks and before the `@custom-variant` lines:

```css
@import "../vendor/animate.css";
```

The file should look like:

```css
/* ... existing @plugin blocks ... */

@import "../vendor/animate.css";

/* Add variants based on LiveView classes */
@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
```

**Step 4: Verify the import works**

```bash
mix assets.build
```

Expected: exits 0 with no errors.

**Step 5: Commit**

```bash
git add assets/vendor/animate.css assets/css/app.css
git commit -m "Add animate.css vendor library"
```

---

### Task 2: Write failing tests for new LiveView event handlers

**Files:**
- Modify: `test/web/live/gallery_live/show_test.exs`

**Step 1: Write the failing tests**

Add these test cases to the existing `Web.GalleryLive.ShowTest` module. Add them after the existing tests:

```elixir
describe "upload modal" do
  test "queue_files event opens upload modal with file list", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

    refute has_element?(view, "#upload-modal")

    render_hook(view, "queue_files", %{
      "files" => [
        %{"name" => "photo1.jpg", "size" => 1024},
        %{"name" => "photo2.jpg", "size" => 2048}
      ]
    })

    assert has_element?(view, "#upload-modal")
    assert has_element?(view, "#upload-modal", "photo1.jpg")
    assert has_element?(view, "#upload-modal", "photo2.jpg")
  end

  test "close_upload_modal closes the modal when status is done", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

    render_hook(view, "queue_files", %{
      "files" => [%{"name" => "photo1.jpg", "size" => 1024}]
    })

    assert has_element?(view, "#upload-modal")

    # Simulate done state by calling close (in production this fires after all done)
    render_hook(view, "close_upload_modal", %{})

    refute has_element?(view, "#upload-modal")
  end

  test "cancel_upload_modal shows confirmation when files are pending", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

    render_hook(view, "queue_files", %{
      "files" => [
        %{"name" => "photo1.jpg", "size" => 1024},
        %{"name" => "photo2.jpg", "size" => 2048}
      ]
    })

    render_hook(view, "cancel_upload_modal", %{})

    assert has_element?(view, "#upload-cancel-confirm")
  end

  test "confirm_cancel_upload closes modal and clears queue", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")

    render_hook(view, "queue_files", %{
      "files" => [%{"name" => "photo1.jpg", "size" => 1024}]
    })

    render_hook(view, "cancel_upload_modal", %{})
    render_hook(view, "confirm_cancel_upload", %{})

    refute has_element?(view, "#upload-modal")
    refute has_element?(view, "#upload-cancel-confirm")
  end
end
```

**Step 2: Run the tests to confirm they fail**

```bash
mix test test/web/live/gallery_live/show_test.exs
```

Expected: 4 new tests fail with errors like `render_hook is undefined` or element not found.

---

### Task 3: Implement new LiveView event handlers in show.ex

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex`

**Step 1: Update `mount/3` to add new assigns and enable auto_upload**

Replace the existing `mount/3` function:

```elixir
@impl true
def mount(%{"id" => id}, _session, socket) do
  gallery = Galleries.get_gallery!(id)

  if connected?(socket) do
    Phoenix.PubSub.subscribe(Family.PubSub, "gallery:#{id}")
  end

  {:ok,
   socket
   |> assign(:gallery, gallery)
   |> assign(:grid_layout, :masonry)
   |> assign(:selection_mode, false)
   |> assign(:selected_ids, MapSet.new())
   |> assign(:confirm_delete_photos, false)
   |> assign(:selected_photo, nil)
   |> assign(:upload_modal, nil)
   |> assign(:upload_queue, [])
   |> assign(:upload_cancel_confirm, false)
   |> stream(:photos, Galleries.list_photos(id))
   |> allow_upload(:photos,
     accept: ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif),
     max_entries: 10,
     max_file_size: 300 * 1_048_576,
     auto_upload: true
   )}
end
```

**Step 2: Add the `queue_files` event handler**

Add this handler after the existing `handle_event("validate", ...)`:

```elixir
def handle_event("queue_files", %{"files" => files}, socket) do
  upload_queue =
    Enum.map(files, fn %{"name" => name, "size" => size} ->
      %{name: name, size: size, status: :pending, error: nil}
    end)

  {:noreply,
   socket
   |> assign(:upload_modal, :uploading)
   |> assign(:upload_queue, upload_queue)
   |> assign(:upload_cancel_confirm, false)}
end
```

**Step 3: Update `upload_photos` to push `batch_complete` and update queue statuses**

Replace the existing `handle_event("upload_photos", ...)`:

```elixir
def handle_event("upload_photos", _params, socket) do
  gallery = socket.assigns.gallery

  {uploaded, errored} =
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
        {:ok, photo} ->
          Oban.insert!(Family.Workers.ProcessPhotoJob.new(%{photo_id: photo.id}))
          {:ok, {:ok, photo}}

        {:error, _} = err ->
          {:ok, {:error, entry.client_name}}
      end
    end)
    |> Enum.split_with(fn
      {:ok, _} -> true
      {:error, _} -> false
    end)

  uploaded_photos = Enum.map(uploaded, fn {:ok, photo} -> photo end)
  errored_names = Enum.map(errored, fn {:error, name} -> name end)

  upload_queue =
    Enum.map(socket.assigns.upload_queue, fn file ->
      cond do
        Enum.any?(uploaded_photos, &(&1.original_filename == file.name)) ->
          %{file | status: :done}

        file.name in errored_names ->
          %{file | status: :error, error: "Upload failed"}

        true ->
          file
      end
    end)

  all_done? = Enum.all?(upload_queue, &(&1.status in [:done, :error]))
  upload_modal = if all_done?, do: :done, else: :uploading

  socket =
    socket
    |> assign(:upload_queue, upload_queue)
    |> assign(:upload_modal, upload_modal)
    |> push_event("batch_complete", %{})

  socket = Enum.reduce(uploaded_photos, socket, &stream_insert(&2, :photos, &1))
  {:noreply, socket}
end
```

**Step 4: Add modal control event handlers**

Add these after the `upload_photos` handler:

```elixir
def handle_event("close_upload_modal", _, socket) do
  {:noreply,
   socket
   |> assign(:upload_modal, nil)
   |> assign(:upload_queue, [])
   |> assign(:upload_cancel_confirm, false)}
end

def handle_event("cancel_upload_modal", _, socket) do
  pending_count =
    Enum.count(socket.assigns.upload_queue, &(&1.status == :pending))

  if pending_count > 0 do
    {:noreply, assign(socket, :upload_cancel_confirm, true)}
  else
    {:noreply,
     socket
     |> assign(:upload_modal, nil)
     |> assign(:upload_queue, [])
     |> assign(:upload_cancel_confirm, false)}
  end
end

def handle_event("confirm_cancel_upload", _, socket) do
  {:noreply,
   socket
   |> assign(:upload_modal, nil)
   |> assign(:upload_queue, [])
   |> assign(:upload_cancel_confirm, false)}
end

def handle_event("dismiss_cancel_confirm", _, socket) do
  {:noreply, assign(socket, :upload_cancel_confirm, false)}
end
```

**Step 5: Run the tests**

```bash
mix test test/web/live/gallery_live/show_test.exs
```

Expected: The 4 new upload modal tests pass. Existing tests may fail due to template changes coming next — that is expected at this stage.

**Step 6: Commit**

```bash
git add lib/web/live/gallery_live/show.ex test/web/live/gallery_live/show_test.exs
git commit -m "Add upload modal state management and event handlers"
```

---

### Task 4: Create the UploadQueue JS hook

**Files:**
- Create: `assets/js/upload_queue.js`

**Step 1: Create the hook file**

Create `assets/js/upload_queue.js` with this content:

```javascript
const UploadQueue = {
  mounted() {
    this.queue = []
    this.currentBatch = []
    this.awaitingBatchComplete = false
    this.feedingBatch = false
    this.dragCounter = 0

    this.fileInput = document.getElementById("photo-file-input")

    // File input change: user selected files via OS picker
    this.fileInput.addEventListener("change", (e) => {
      if (this.feedingBatch) return
      const files = Array.from(e.target.files)
      if (files.length > 0) this.queueFiles(files)
    })

    // Drag events on the gallery wrapper
    this.el.addEventListener("dragenter", (e) => {
      e.preventDefault()
      this.dragCounter++
      if (this.dragCounter === 1) this.showDragOverlay(e)
    })

    this.el.addEventListener("dragleave", (e) => {
      e.preventDefault()
      this.dragCounter--
      if (this.dragCounter === 0) this.hideDragOverlay()
    })

    this.el.addEventListener("dragover", (e) => {
      e.preventDefault()
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      this.dragCounter = 0
      this.hideDragOverlay()

      const files = Array.from(e.dataTransfer.files).filter(
        (f) => f.type.startsWith("image/") || f.name.match(/\.(dng|nef|tiff?|raw)$/i)
      )
      if (files.length > 0) this.queueFiles(files)
    })

    // Server signals current batch is fully consumed — feed next
    this.handleEvent("batch_complete", () => {
      this.awaitingBatchComplete = false
      this.feedNextBatch()
    })
  },

  updated() {
    if (this.awaitingBatchComplete || this.currentBatch.length === 0) return

    const entries = this.el.querySelectorAll("[data-upload-entry]")
    if (entries.length !== this.currentBatch.length) return

    const allSettled = Array.from(entries).every(
      (e) => parseInt(e.dataset.progress || "0") === 100 || e.dataset.error === "true"
    )

    if (allSettled) {
      this.awaitingBatchComplete = true
      this.pushEvent("upload_photos", {})
    }
  },

  queueFiles(files) {
    this.queue = [...files]

    this.pushEvent("queue_files", {
      files: files.map((f) => ({ name: f.name, size: f.size })),
    })

    this.feedNextBatch()
  },

  feedNextBatch() {
    if (this.queue.length === 0) {
      this.currentBatch = []
      return
    }

    const batch = this.queue.splice(0, 10)
    this.currentBatch = batch

    const dt = new DataTransfer()
    batch.forEach((f) => dt.items.add(f))

    this.feedingBatch = true
    this.fileInput.files = dt.files
    this.fileInput.dispatchEvent(new Event("change", { bubbles: true }))
    this.feedingBatch = false
  },

  showDragOverlay(e) {
    const count = e.dataTransfer?.items?.length || 0
    const overlay = document.getElementById("drag-overlay")
    if (!overlay) return
    const label = overlay.querySelector("[data-drag-count]")
    if (label) {
      label.textContent = `Drop to upload ${count} photo${count !== 1 ? "s" : ""}`
    }
    overlay.classList.remove("hidden")
  },

  hideDragOverlay() {
    const overlay = document.getElementById("drag-overlay")
    if (overlay) overlay.classList.add("hidden")
  },
}

export default UploadQueue
```

**Step 2: Verify the file was created**

```bash
cat assets/js/upload_queue.js | head -5
```

Expected: shows the `const UploadQueue = {` line.

---

### Task 5: Register the hook in app.js

**Files:**
- Modify: `assets/js/app.js`

**Step 1: Import the hook and register it with LiveSocket**

Add the import after the existing imports, and spread it into the hooks object:

```javascript
// Add after the existing imports (before the csrfToken line):
import UploadQueue from "./upload_queue"

// Update the LiveSocket constructor to include the hook:
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, UploadQueue},
})
```

**Step 2: Verify the build succeeds**

```bash
mix assets.build
```

Expected: exits 0 with no errors.

**Step 3: Commit**

```bash
git add assets/js/upload_queue.js assets/js/app.js
git commit -m "Add UploadQueue JS hook for batched file uploads"
```

---

### Task 6: Update the gallery show template

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex`

**Step 1: Replace the entire template**

Replace the contents of `lib/web/live/gallery_live/show.html.heex` with the following. Read the current file first so you can see exactly what is being changed.

```heex
<Layouts.app flash={@flash}>
  <%!-- Hidden form required by LiveView for file uploads --%>
  <form id="upload-form" phx-change="validate" phx-submit="upload_photos" class="hidden">
    <.live_file_input upload={@uploads.photos} id="photo-file-input" />
  </form>

  <%!-- Drag & drop overlay (shown by JS hook on dragenter) --%>
  <div
    id="drag-overlay"
    class="hidden fixed inset-0 z-40 pointer-events-none flex items-center justify-center"
  >
    <div class="absolute inset-4 rounded-3xl border-4 border-dashed border-primary/60 bg-primary/10 backdrop-blur-sm">
    </div>
    <div class="relative z-10 text-center">
      <.icon name="hero-cloud-arrow-up" class="w-16 h-16 text-primary mx-auto mb-3" />
      <p class="text-2xl font-bold text-primary" data-drag-count>Drop to upload photos</p>
    </div>
  </div>

  <div
    id="gallery-wrapper"
    phx-hook="UploadQueue"
    phx-drop-target={@uploads.photos.ref}
    class="max-w-7xl mx-auto px-4 sm:px-6 py-8"
  >
    <%!-- Header --%>
    <div class="flex items-center justify-between mb-6">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/galleries"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">{@gallery.name}</h1>
      </div>
      <div class="flex items-center gap-2">
        <%!-- Upload button --%>
        <button
          id="upload-btn"
          type="button"
          onclick="document.getElementById('photo-file-input').click()"
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary text-primary-content hover:bg-primary/90 text-sm font-medium transition-colors"
        >
          <.icon name="hero-cloud-arrow-up" class="w-4 h-4" /> Upload
        </button>
        <button
          id="layout-toggle"
          phx-click="toggle_layout"
          class="p-2 rounded-lg text-base-content/50 hover:text-base-content hover:bg-base-200 transition-colors"
          title={
            if @grid_layout == :masonry, do: "Switch to uniform grid", else: "Switch to masonry"
          }
        >
          <%= if @grid_layout == :masonry do %>
            <.icon name="hero-squares-2x2" class="w-5 h-5" />
          <% else %>
            <.icon name="hero-rectangle-stack" class="w-5 h-5" />
          <% end %>
        </button>
        <button
          id="select-btn"
          phx-click="toggle_select_mode"
          class={[
            "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
            if(@selection_mode,
              do: "bg-primary text-primary-content",
              else: "bg-base-200 text-base-content hover:bg-base-300"
            )
          ]}
        >
          {if @selection_mode, do: "Cancel", else: "Select"}
        </button>
      </div>
    </div>

    <%!-- Selection bar --%>
    <%= if @selection_mode do %>
      <div
        id="selection-bar"
        class="mb-4 flex items-center justify-between bg-base-content text-base-100 rounded-xl px-5 py-3"
      >
        <span class="text-sm font-medium">{MapSet.size(@selected_ids)} selected</span>
        <button
          phx-click="request_delete_photos"
          disabled={MapSet.size(@selected_ids) == 0}
          class="px-3 py-1.5 bg-error hover:bg-error/80 disabled:opacity-40 disabled:cursor-not-allowed text-white rounded-lg text-sm font-medium transition-colors"
        >
          Delete
        </button>
      </div>
    <% end %>

    <%!-- Photo grid --%>
    <div
      id="photo-grid"
      phx-update="stream"
      class={[
        if(@grid_layout == :masonry,
          do: "masonry-grid columns-2 sm:columns-3 md:columns-4 lg:columns-5 gap-2",
          else: "uniform-grid grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-2"
        )
      ]}
    >
      <div
        id="photos-empty"
        class="hidden only:block col-span-full text-center py-20 text-base-content/30"
      >
        No photos yet
      </div>
      <div
        :for={{id, photo} <- @streams.photos}
        id={id}
        class={[
          "relative group rounded-xl overflow-hidden bg-base-200 cursor-pointer",
          @grid_layout == :masonry && "mb-2 break-inside-avoid"
        ]}
        phx-click={
          if @selection_mode,
            do: JS.push("toggle_photo_select", value: %{id: photo.id}),
            else: JS.push("open_lightbox", value: %{id: photo.id})
        }
      >
        <%= cond do %>
          <% photo.status == "pending" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2">
              <.icon
                name="hero-photo"
                class="w-8 h-8 text-base-content/20 animate__animated animate__pulse animate__infinite"
              />
              <p class="text-xs text-base-content/30 font-medium">Processing</p>
            </div>
          <% photo.status == "failed" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2 bg-error/5">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-error/50" />
              <p class="text-xs text-error/70">Processing failed</p>
            </div>
          <% true -> %>
            <img
              src={Family.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
              alt={photo.original_filename}
              class="w-full h-full object-cover"
              loading="lazy"
            />
        <% end %>

        <%!-- Selection overlay --%>
        <%= if @selection_mode do %>
          <div class={[
            "absolute inset-0 transition-colors",
            MapSet.member?(@selected_ids, photo.id) && "bg-primary/30"
          ]}>
            <div class={[
              "absolute top-2 right-2 w-6 h-6 rounded-full border-2 transition-all flex items-center justify-center",
              if(MapSet.member?(@selected_ids, photo.id),
                do: "bg-primary border-primary",
                else: "border-white/70 bg-black/20"
              )
            ]}>
              <%= if MapSet.member?(@selected_ids, photo.id) do %>
                <.icon name="hero-check" class="w-3.5 h-3.5 text-white" />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  </div>

  <%!-- Upload progress modal --%>
  <%= if @upload_modal do %>
    <div class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm"></div>
      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-lg flex flex-col max-h-[80vh]">
        <%!-- Modal header --%>
        <div class="flex items-center justify-between px-6 py-4 border-b border-base-200 shrink-0">
          <%= if @upload_modal == :done do %>
            <h2 class="text-lg font-semibold text-base-content">
              <%= if Enum.any?(@upload_queue, &(&1.status == :error)) do %>
                Upload complete with errors
              <% else %>
                Upload complete
              <% end %>
            </h2>
          <% else %>
            <h2 class="text-lg font-semibold text-base-content">
              Uploading photos ({Enum.count(@upload_queue, &(&1.status == :done))} of {length(@upload_queue)})
            </h2>
          <% end %>
          <button
            phx-click={if @upload_modal == :done, do: "close_upload_modal", else: "cancel_upload_modal"}
            class="p-1.5 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Cancel confirmation --%>
        <%= if @upload_cancel_confirm do %>
          <div id="upload-cancel-confirm" class="px-6 py-4 bg-warning/10 border-b border-warning/20 shrink-0">
            <p class="text-sm font-medium text-base-content mb-3">
              {Enum.count(@upload_queue, &(&1.status == :pending))} files haven't uploaded yet. Cancel anyway?
            </p>
            <div class="flex gap-2">
              <button
                phx-click="confirm_cancel_upload"
                class="px-3 py-1.5 bg-error text-white rounded-lg text-sm font-medium hover:bg-error/90 transition-colors"
              >
                Yes, cancel
              </button>
              <button
                phx-click="dismiss_cancel_confirm"
                class="px-3 py-1.5 bg-base-200 text-base-content rounded-lg text-sm font-medium hover:bg-base-300 transition-colors"
              >
                Keep uploading
              </button>
            </div>
          </div>
        <% end %>

        <%!-- File list --%>
        <div class="overflow-y-auto flex-1 px-6 py-4 space-y-2">
          <%!-- Errors first when done --%>
          <%= if @upload_modal == :done do %>
            <%= for file <- Enum.filter(@upload_queue, &(&1.status == :error)) do %>
              <div class="flex items-center gap-3 bg-error/5 border border-error/20 rounded-xl px-4 py-3">
                <.icon name="hero-x-circle" class="w-5 h-5 text-error shrink-0" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-base-content truncate">{file.name}</p>
                  <p class="text-xs text-error mt-0.5">{file.error || "Upload failed"}</p>
                </div>
              </div>
            <% end %>
            <%!-- Successful uploads --%>
            <%= for file <- Enum.filter(@upload_queue, &(&1.status == :done)) do %>
              <div class="flex items-center gap-3 bg-success/5 border border-success/20 rounded-xl px-4 py-3">
                <.icon name="hero-check-circle" class="w-5 h-5 text-success shrink-0" />
                <p class="text-sm font-medium text-base-content truncate flex-1">{file.name}</p>
              </div>
            <% end %>
          <% else %>
            <%!-- In-progress view: show all files with live progress --%>
            <%= for file <- @upload_queue do %>
              <% entry = Enum.find(@uploads.photos.entries, &(&1.client_name == file.name)) %>
              <div
                data-upload-entry
                data-progress={if entry, do: entry.progress, else: if(file.status == :done, do: 100, else: 0)}
                data-error={if upload_errors(@uploads.photos, entry || %Phoenix.LiveView.UploadEntry{}) != [], do: "true", else: "false"}
                class="flex items-center gap-3 bg-base-100 rounded-xl border border-base-200 px-4 py-3"
              >
                <%= cond do %>
                  <% file.status == :done -> %>
                    <.icon name="hero-check-circle" class="w-5 h-5 text-success shrink-0" />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-base-content truncate">{file.name}</p>
                    </div>
                  <% file.status == :error -> %>
                    <.icon name="hero-x-circle" class="w-5 h-5 text-error shrink-0" />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-base-content truncate">{file.name}</p>
                      <p class="text-xs text-error mt-0.5">{file.error || "Failed"}</p>
                    </div>
                  <% entry != nil -> %>
                    <.icon name="hero-arrow-up-tray" class="w-5 h-5 text-primary shrink-0" />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-base-content truncate">{file.name}</p>
                      <div class="mt-1.5 h-1.5 bg-base-200 rounded-full overflow-hidden">
                        <div
                          class="h-full bg-primary rounded-full transition-all duration-300"
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>
                      <%= for err <- upload_errors(@uploads.photos, entry) do %>
                        <p class="text-xs text-error mt-1">{upload_error_to_string(err)}</p>
                      <% end %>
                    </div>
                  <% true -> %>
                    <.icon name="hero-clock" class="w-5 h-5 text-base-content/30 shrink-0" />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-base-content/50 truncate">{file.name}</p>
                      <p class="text-xs text-base-content/30 mt-0.5">Waiting…</p>
                    </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>

        <%!-- Modal footer --%>
        <div class="px-6 py-4 border-t border-base-200 shrink-0">
          <%= if @upload_modal == :done do %>
            <button
              phx-click="close_upload_modal"
              class="w-full px-4 py-2 bg-primary text-primary-content rounded-xl font-medium hover:bg-primary/90 transition-colors"
            >
              Done
            </button>
          <% else %>
            <button
              phx-click="cancel_upload_modal"
              class="w-full px-4 py-2 bg-base-200 text-base-content rounded-xl font-medium hover:bg-base-300 transition-colors"
            >
              Cancel
            </button>
          <% end %>
        </div>
      </div>
    </div>
  <% end %>

  <%!-- Lightbox --%>
  <%= if @selected_photo do %>
    <div
      id="lightbox"
      class="fixed inset-0 z-50 bg-black/95 flex flex-col select-none"
      phx-window-keydown="lightbox_keydown"
    >
      <%!-- Lightbox top bar --%>
      <div class="flex items-center justify-between px-6 py-4 shrink-0">
        <p class="text-white/50 text-sm truncate max-w-xs">{@selected_photo.original_filename}</p>
        <div class="flex items-center gap-3">
          <a
            href={Family.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :original)}
            download={@selected_photo.original_filename}
            class="flex items-center gap-1.5 px-3 py-1.5 bg-white/10 hover:bg-white/20 text-white rounded-lg text-sm font-medium transition-colors"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Download original
          </a>
          <button
            phx-click="close_lightbox"
            class="p-2 text-white/50 hover:text-white rounded-lg hover:bg-white/10 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
      </div>

      <%!-- Main image area --%>
      <div class="flex-1 flex items-center justify-center relative min-h-0 px-16">
        <button
          phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowLeft"})}
          class="absolute left-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
        >
          <.icon name="hero-chevron-left" class="w-7 h-7" />
        </button>

        <img
          src={Family.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
          alt={@selected_photo.original_filename}
          class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
        />

        <button
          phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowRight"})}
          class="absolute right-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
        >
          <.icon name="hero-chevron-right" class="w-7 h-7" />
        </button>
      </div>

      <%!-- Thumbnail strip --%>
      <div class="shrink-0 flex gap-2 px-6 py-4 overflow-x-auto">
        <%= for photo <- Galleries.list_photos(@gallery.id) do %>
          <button
            phx-click="lightbox_select"
            phx-value-id={photo.id}
            class={[
              "shrink-0 w-16 h-16 rounded-lg overflow-hidden border-2 transition-all duration-150",
              if(photo.id == @selected_photo.id,
                do: "border-white scale-105 shadow-lg",
                else: "border-transparent opacity-50 hover:opacity-90"
              )
            ]}
          >
            <%= if photo.status == "processed" do %>
              <img
                src={Family.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
                alt={photo.original_filename}
                class="w-full h-full object-cover"
              />
            <% else %>
              <div class="w-full h-full bg-white/10 flex items-center justify-center">
                <.icon name="hero-photo" class="w-5 h-5 text-white/30" />
              </div>
            <% end %>
          </button>
        <% end %>
      </div>
    </div>
  <% end %>

  <%!-- Delete photos confirmation modal --%>
  <%= if @confirm_delete_photos do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete_photos">
      </div>
      <div class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8">
        <h2 class="text-xl font-bold text-base-content mb-2">Delete Photos</h2>
        <p class="text-base-content/60 mb-6">
          Delete {MapSet.size(@selected_ids)} photo(s)? This cannot be undone.
        </p>
        <div class="flex gap-3">
          <button phx-click="confirm_delete_photos" class="btn btn-error flex-1">Delete</button>
          <button phx-click="cancel_delete_photos" class="btn btn-ghost flex-1">Cancel</button>
        </div>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

**Note on the `data-error` attribute in the file list:** The template checks `upload_errors` for each entry to set `data-error`. For queue items without a matching LiveView entry (status `:pending` or `:done`), we pass a blank struct to avoid a crash. If this causes issues, simplify the `data-error` check to just `"false"` for non-entry rows — the JS hook only needs this for active upload entries.

**Step 2: Run all tests to see what's passing**

```bash
mix test test/web/live/gallery_live/show_test.exs
```

Expected: the `shows gallery name and upload area` test will fail (we removed `upload-area`). Update that test:

```elixir
test "shows gallery name and upload button", %{conn: conn, gallery: gallery} do
  {:ok, _view, html} = live(conn, ~p"/galleries/#{gallery.id}")
  assert html =~ gallery.name
  assert html =~ "upload-btn"
end
```

**Step 3: Run all tests**

```bash
mix test test/web/live/gallery_live/show_test.exs
```

Expected: all tests pass.

**Step 4: Commit**

```bash
git add lib/web/live/gallery_live/show.html.heex test/web/live/gallery_live/show_test.exs
git commit -m "Update gallery show template with drag & drop, upload modal, and processing placeholders"
```

---

### Task 7: Run precommit and fix any issues

**Step 1: Run the full precommit check**

```bash
mix precommit
```

Expected: compiles with no warnings, format passes, all tests pass.

**Step 2: Fix any compilation warnings**

Common issues to watch for:
- Unused variables — prefix with `_`
- Missing function clauses — add catch-all clauses
- Module attribute warnings — check `allow_upload` options

**Step 3: If all green, commit the fix**

```bash
git add -p
git commit -m "Fix precommit issues"
```

---

## Notes for the Implementer

### How `auto_upload: true` changes the flow

With `auto_upload: true` in `allow_upload`, Phoenix LiveView starts uploading files immediately when they are added to the file input — no form submission needed to start the transfer. `consume_uploaded_entries` can be called from any `handle_event`, which is why `upload_photos` works as a regular event (not a form submit).

### The DataTransfer API trick

The JS hook feeds batches by programmatically setting `fileInput.files` using the `DataTransfer` API:

```javascript
const dt = new DataTransfer()
batch.forEach(f => dt.items.add(f))
fileInput.files = dt.files
fileInput.dispatchEvent(new Event("change", { bubbles: true }))
```

This is supported in all modern browsers. LiveView's upload JS handler listens for the `change` event on the file input element and registers the new entries.

### The `updated()` detection mechanism

The hook detects batch completion by observing DOM elements with `[data-upload-entry]`. Each entry in the modal has `data-progress={entry.progress}`. When all entries in the current batch reach 100% (or have errors), the hook pushes `upload_photos`. The `awaitingBatchComplete` flag prevents double-firing.

### Matching queue files to LiveView entries

The modal template matches `@upload_queue` items to `@uploads.photos.entries` by `client_name`. Duplicate filenames within the same upload session are possible but unlikely in a family photo app — this is an acceptable limitation.
