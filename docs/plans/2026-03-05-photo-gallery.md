# Photo Gallery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a shared photo gallery where users create named galleries, upload photos (including RAW formats), view them in a masonry/uniform grid, and browse them in a full-screen lightbox.

**Architecture:** Galleries and photos are stored in Postgres. Photos are uploaded via Phoenix LiveView with per-file progress bars. On upload, originals are saved to disk and a `Photo` record is created with `status: "pending"`. An Oban job generates the three image versions (original, large, thumbnail) asynchronously using ImageMagick via Waffle. PubSub broadcasts completion events to the LiveView which updates the stream in real time. Waffle abstracts storage so switching to S3 later requires only a config change.

**Tech Stack:** Phoenix 1.8 + LiveView 1.1, Ecto/Postgres, Waffle + Waffle.Ecto (file storage), Oban 2.18 (background jobs), ImageMagick (image transforms via Waffle), Tailwind CSS v4

---

### Task 1: Add dependencies

**Files:**
- Modify: `mix.exs`

**Step 1: Add deps**

In the `deps/0` list in `mix.exs`, add:

```elixir
{:waffle, "~> 1.1"},
{:waffle_ecto, "~> 0.0.12"},
{:oban, "~> 2.18"},
```

**Step 2: Fetch deps**

```bash
mix deps.get
```

Expected: packages downloaded successfully.

**Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "Add waffle, waffle_ecto, and oban dependencies"
```

---

### Task 2: Configure Waffle, Oban, and static paths

**Files:**
- Modify: `config/config.exs`
- Modify: `config/test.exs`
- Modify: `lib/family/application.ex`
- Modify: `lib/web.ex`

**Step 1: Add Waffle and Oban config to `config/config.exs`**

Add after the existing `config :family` block:

```elixir
config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir_prefix: "priv/static"

config :family, Oban,
  engine: Oban.Engines.Basic,
  repo: Family.Repo,
  queues: [photos: 5]
```

**Step 2: Add test overrides to `config/test.exs`**

Add:

```elixir
config :waffle,
  storage: Waffle.Storage.Local,
  storage_dir_prefix: "tmp/test_uploads"

config :family, Oban, testing: :inline
```

**Step 3: Add Oban to the supervision tree in `lib/family/application.ex`**

In the `children` list, add before `Web.Endpoint`:

```elixir
{Oban, Application.fetch_env!(:family, Oban)},
```

**Step 4: Add `"uploads"` to static paths in `lib/web.ex`**

Change:

```elixir
def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
```

To:

```elixir
def static_paths, do: ~w(assets fonts images favicon.ico robots.txt uploads)
```

This allows Phoenix to serve photos from `priv/static/uploads/`.

**Step 5: Verify compilation**

```bash
mix compile
```

Expected: compiles without errors.

**Step 6: Commit**

```bash
git add config/config.exs config/test.exs lib/family/application.ex lib/web.ex
git commit -m "Configure Waffle local storage, Oban, and add uploads to static paths"
```

---

### Task 3: Oban jobs table migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_oban_jobs_tables.exs`

**Step 1: Generate migration**

```bash
mix ecto.gen.migration add_oban_jobs_tables
```

**Step 2: Replace the generated `change/0` with separate `up/0` and `down/0`**

Open the generated file. Replace the `def change do ... end` body with:

```elixir
def up do
  Oban.Migration.up(version: 12)
end

def down do
  Oban.Migration.down(version: 1)
end
```

**Step 3: Run migration**

```bash
mix ecto.migrate
```

Expected: migration runs successfully.

**Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "Add Oban jobs table migration"
```

---

### Task 4: Galleries migration, schema, and context

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_galleries.exs`
- Create: `lib/family/galleries/gallery.ex`
- Create: `lib/family/galleries.ex`
- Create: `test/family/galleries_test.exs`

**Step 1: Generate migration**

```bash
mix ecto.gen.migration create_galleries
```

**Step 2: Write migration**

```elixir
def change do
  create table(:galleries) do
    add :name, :string, null: false
    timestamps()
  end
end
```

**Step 3: Run migration**

```bash
mix ecto.migrate
```

**Step 4: Write the failing tests**

Create `test/family/galleries_test.exs`:

```elixir
defmodule Family.GalleriesTest do
  use Family.DataCase, async: true

  alias Family.Galleries
  alias Family.Galleries.Gallery

  describe "galleries" do
    test "list_galleries/0 returns all galleries ordered by inserted_at" do
      g1 = gallery_fixture(%{name: "Alpha"})
      g2 = gallery_fixture(%{name: "Beta"})
      assert Galleries.list_galleries() == [g1, g2]
    end

    test "get_gallery!/1 returns the gallery with given id" do
      gallery = gallery_fixture()
      assert Galleries.get_gallery!(gallery.id) == gallery
    end

    test "create_gallery/1 with valid data creates a gallery" do
      assert {:ok, %Gallery{} = gallery} = Galleries.create_gallery(%{name: "Vacation 2025"})
      assert gallery.name == "Vacation 2025"
    end

    test "create_gallery/1 with blank name returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Galleries.create_gallery(%{name: ""})
    end

    test "delete_gallery/1 deletes the gallery" do
      gallery = gallery_fixture()
      assert {:ok, %Gallery{}} = Galleries.delete_gallery(gallery)
      assert_raise Ecto.NoResultsError, fn -> Galleries.get_gallery!(gallery.id) end
    end

    test "change_gallery/2 returns a gallery changeset" do
      gallery = gallery_fixture()
      assert %Ecto.Changeset{} = Galleries.change_gallery(gallery)
    end
  end

  def gallery_fixture(attrs \\ %{}) do
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery"})
      |> Galleries.create_gallery()

    gallery
  end
end
```

**Step 5: Run test to verify it fails**

```bash
mix test test/family/galleries_test.exs
```

Expected: FAIL — `Family.Galleries` not found.

**Step 6: Create Gallery schema**

Create `lib/family/galleries/gallery.ex`:

```elixir
defmodule Family.Galleries.Gallery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "galleries" do
    field :name, :string
    has_many :photos, Family.Galleries.Photo, on_delete: :delete_all
    timestamps()
  end

  def changeset(gallery, attrs) do
    gallery
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
```

**Step 7: Create Galleries context**

Create `lib/family/galleries.ex`:

```elixir
defmodule Family.Galleries do
  import Ecto.Query
  alias Family.Repo
  alias Family.Galleries.Gallery

  def list_galleries do
    Repo.all(from g in Gallery, order_by: [asc: g.inserted_at])
  end

  def get_gallery!(id), do: Repo.get!(Gallery, id)

  def create_gallery(attrs \\ %{}) do
    %Gallery{}
    |> Gallery.changeset(attrs)
    |> Repo.insert()
  end

  def change_gallery(%Gallery{} = gallery, attrs \\ %{}) do
    Gallery.changeset(gallery, attrs)
  end

  def delete_gallery(%Gallery{} = gallery) do
    Repo.delete(gallery)
  end
end
```

**Step 8: Run tests**

```bash
mix test test/family/galleries_test.exs
```

Expected: all tests pass.

**Step 9: Commit**

```bash
git add lib/family/galleries/ lib/family/galleries.ex priv/repo/migrations/ test/family/galleries_test.exs
git commit -m "Add Gallery schema and context"
```

---

### Task 5: Photos migration

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_photos.exs`

**Step 1: Generate migration**

```bash
mix ecto.gen.migration create_photos
```

**Step 2: Write migration**

```elixir
def change do
  create table(:photos) do
    add :gallery_id, references(:galleries, on_delete: :delete_all), null: false
    add :image, :string
    add :original_path, :string
    add :original_filename, :string
    add :content_type, :string
    add :status, :string, null: false, default: "pending"
    timestamps(updated_at: false)
  end

  create index(:photos, [:gallery_id])
end
```

**Step 3: Run migration**

```bash
mix ecto.migrate
```

**Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "Add photos table migration"
```

---

### Task 6: Waffle photo uploader

**Files:**
- Create: `lib/family/uploaders/photo.ex`

**Step 1: Create the uploader**

Create `lib/family/uploaders/photo.ex`:

```elixir
defmodule Family.Uploaders.Photo do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original, :large, :thumbnail]

  @valid_extensions ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif)

  def versions, do: @versions

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  # Keep the original as-is; large and thumbnail are always output as JPEG
  def transform(:original, _), do: :noaction

  def transform(:large, _) do
    {:convert, "-resize 1920x1920> -auto-orient -strip", :jpg}
  end

  def transform(:thumbnail, _) do
    {:convert, "-resize 400x400> -auto-orient -strip", :jpg}
  end

  # Original keeps its extension; processed versions are always .jpg
  def filename(:original, {file, _}) do
    "original#{Path.extname(file.file_name) |> String.downcase()}"
  end

  def filename(version, _), do: "#{version}.jpg"

  # Files stored at priv/static/uploads/photos/{gallery_id}/{photo_id}/
  def storage_dir(_version, {_file, scope}) do
    "uploads/photos/#{scope.gallery_id}/#{scope.id}"
  end
end
```

**Note:** ImageMagick must be installed on the host (`brew install imagemagick` on macOS, `apt install imagemagick` on Debian/Ubuntu). For RAW files (NEF, DNG), ImageMagick needs to be compiled with RAW support (usually via `ufraw` or `dcraw`). Verify with `identify -list format | grep -i nef`.

**Step 2: Verify compilation**

```bash
mix compile
```

Expected: compiles without errors.

**Step 3: Commit**

```bash
git add lib/family/uploaders/
git commit -m "Add Waffle photo uploader with original, large, and thumbnail versions"
```

---

### Task 7: Photo schema and context functions

**Files:**
- Create: `lib/family/galleries/photo.ex`
- Modify: `lib/family/galleries.ex`
- Modify: `test/family/galleries_test.exs`

**Step 1: Add photo tests to `test/family/galleries_test.exs`**

Add below the existing `describe "galleries"` block. You'll also need `gallery_fixture/1` to be accessible — move it to a module-level `defp` if needed or keep it as-is since it's already defined:

```elixir
describe "photos" do
  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test"})
    %{gallery: gallery}
  end

  test "list_photos/1 returns photos ordered by inserted_at asc", %{gallery: gallery} do
    {:ok, p1} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/a.jpg",
      original_filename: "a.jpg",
      content_type: "image/jpeg"
    })
    {:ok, p2} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/b.jpg",
      original_filename: "b.jpg",
      content_type: "image/jpeg"
    })
    assert Galleries.list_photos(gallery.id) == [p1, p2]
  end

  test "create_photo/1 creates a pending photo", %{gallery: gallery} do
    assert {:ok, photo} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/test.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg"
    })
    assert photo.status == "pending"
    assert photo.gallery_id == gallery.id
  end

  test "delete_photo/1 deletes the photo", %{gallery: gallery} do
    {:ok, photo} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/test.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg"
    })
    assert {:ok, _} = Galleries.delete_photo(photo)
    assert Galleries.list_photos(gallery.id) == []
  end

  test "update_photo_processed/2 sets status to processed", %{gallery: gallery} do
    {:ok, photo} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/test.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg"
    })
    assert {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
    assert updated.status == "processed"
  end

  test "update_photo_failed/1 sets status to failed", %{gallery: gallery} do
    {:ok, photo} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/test.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg"
    })
    assert {:ok, updated} = Galleries.update_photo_failed(photo)
    assert updated.status == "failed"
  end
end
```

**Step 2: Run tests to verify failure**

```bash
mix test test/family/galleries_test.exs
```

Expected: FAIL — `Galleries.create_photo/1` not found.

**Step 3: Create Photo schema**

Create `lib/family/galleries/photo.ex`:

```elixir
defmodule Family.Galleries.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    field :image, Family.Uploaders.Photo.Type
    field :original_path, :string
    field :original_filename, :string
    field :content_type, :string
    field :status, :string, default: "pending"
    belongs_to :gallery, Family.Galleries.Gallery
    timestamps(updated_at: false)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:gallery_id, :original_path, :original_filename, :content_type, :status])
    |> validate_required([:gallery_id, :original_path, :original_filename, :content_type])
    |> foreign_key_constraint(:gallery_id)
  end

  def processed_changeset(photo, attrs) do
    photo
    |> cast_attachments(attrs, [:image])
    |> cast(attrs, [:status])
  end
end
```

**Step 4: Add photo functions to `lib/family/galleries.ex`**

Add this alias at the top of the module (alongside the existing `Gallery` alias):

```elixir
alias Family.Galleries.Photo
```

Then add these functions:

```elixir
def list_photos(gallery_id) do
  Repo.all(
    from p in Photo,
      where: p.gallery_id == ^gallery_id,
      order_by: [asc: p.inserted_at]
  )
end

def get_photo!(id), do: Repo.get!(Photo, id)

def create_photo(attrs \\ %{}) do
  %Photo{}
  |> Photo.changeset(attrs)
  |> Repo.insert()
end

def delete_photo(%Photo{} = photo) do
  Family.Uploaders.Photo.delete({photo.image, photo})
  Repo.delete(photo)
end

def update_photo_processed(%Photo{} = photo, filename) do
  photo
  |> Photo.processed_changeset(%{image: filename, status: "processed"})
  |> Repo.update()
end

def update_photo_failed(%Photo{} = photo) do
  photo
  |> Ecto.Changeset.change(%{status: "failed"})
  |> Repo.update()
end
```

**Step 5: Run tests**

```bash
mix test test/family/galleries_test.exs
```

Expected: all tests pass.

**Step 6: Commit**

```bash
git add lib/family/galleries/photo.ex lib/family/galleries.ex test/family/galleries_test.exs
git commit -m "Add Photo schema and photo context functions"
```

---

### Task 8: ProcessPhotoJob Oban worker

**Files:**
- Create: `lib/family/workers/process_photo_job.ex`
- Create: `test/fixtures/test_image.jpg`
- Create: `test/family/workers/process_photo_job_test.exs`

**Step 1: Create a small test fixture image**

Run (requires ImageMagick):

```bash
mkdir -p test/fixtures
convert -size 200x150 xc:steelblue test/fixtures/test_image.jpg
```

**Step 2: Write the failing test**

Create `test/family/workers/process_photo_job_test.exs`:

```elixir
defmodule Family.Workers.ProcessPhotoJobTest do
  use Family.DataCase, async: false
  use Oban.Testing, repo: Family.Repo

  alias Family.Workers.ProcessPhotoJob
  alias Family.Galleries

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test"})

    tmp_dir = Path.join(System.tmp_dir!(), "photo_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    original_path = Path.join(tmp_dir, "photo.jpg")
    File.cp!(Path.join(__DIR__, "../../fixtures/test_image.jpg"), original_path)

    {:ok, photo} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: original_path,
      original_filename: "test_image.jpg",
      content_type: "image/jpeg"
    })

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{photo: photo, gallery: gallery}
  end

  test "performs job: processes photo and broadcasts :photo_processed", %{photo: photo, gallery: gallery} do
    Phoenix.PubSub.subscribe(Family.PubSub, "gallery:#{gallery.id}")

    assert :ok = perform_job(ProcessPhotoJob, %{photo_id: photo.id})

    updated = Galleries.get_photo!(photo.id)
    assert updated.status == "processed"
    assert updated.image != nil

    assert_receive {:photo_processed, ^updated}
  end

  test "marks photo as failed and broadcasts :photo_failed when original_path is missing", %{photo: photo, gallery: gallery} do
    Phoenix.PubSub.subscribe(Family.PubSub, "gallery:#{gallery.id}")

    # Point original_path at a nonexistent file
    photo = %{photo | original_path: "/nonexistent/photo.jpg"}

    # Directly test the processing logic via perform
    assert {:error, _reason} = ProcessPhotoJob.perform(%Oban.Job{args: %{"photo_id" => photo.id}})

    updated = Galleries.get_photo!(photo.id)
    assert updated.status == "failed"

    assert_receive {:photo_failed, _}
  end
end
```

**Step 3: Run test to verify failure**

```bash
mix test test/family/workers/process_photo_job_test.exs
```

Expected: FAIL — `Family.Workers.ProcessPhotoJob` not found.

**Step 4: Create the Oban worker**

Create `lib/family/workers/process_photo_job.ex`:

```elixir
defmodule Family.Workers.ProcessPhotoJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Family.Galleries
  alias Family.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
    photo = Galleries.get_photo!(photo_id)

    case process_photo(photo) do
      {:ok, updated_photo} ->
        Phoenix.PubSub.broadcast(
          Family.PubSub,
          "gallery:#{photo.gallery_id}",
          {:photo_processed, updated_photo}
        )
        :ok

      {:error, reason} ->
        {:ok, _} = Galleries.update_photo_failed(photo)

        Phoenix.PubSub.broadcast(
          Family.PubSub,
          "gallery:#{photo.gallery_id}",
          {:photo_failed, photo}
        )

        {:error, reason}
    end
  end

  defp process_photo(photo) do
    waffle_file = %Waffle.File{
      path: photo.original_path,
      file_name: Path.basename(photo.original_path)
    }

    case Uploaders.Photo.store({waffle_file, photo}) do
      {:ok, filename} -> Galleries.update_photo_processed(photo, filename)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Step 5: Run tests**

```bash
mix test test/family/workers/process_photo_job_test.exs
```

Expected: all tests pass (requires ImageMagick installed).

**Step 6: Commit**

```bash
git add lib/family/workers/ test/family/workers/ test/fixtures/
git commit -m "Add ProcessPhotoJob Oban worker with PubSub broadcast"
```

---

### Task 9: Router updates

**Files:**
- Modify: `lib/web/router.ex`

**Step 1: Add gallery routes**

Replace the existing `scope "/", Web do` block with:

```elixir
scope "/", Web do
  pipe_through :browser

  live_session :default do
    live "/galleries", GalleryLive.Index, :index
    live "/galleries/:id", GalleryLive.Show, :show
  end

  get "/", PageController, :home
end
```

**Step 2: Verify compilation**

```bash
mix compile
```

Expected: compiles (warnings about missing GalleryLive modules are fine at this stage).

**Step 3: Commit**

```bash
git add lib/web/router.ex
git commit -m "Add gallery LiveView routes"
```

---

### Task 10: Gallery index LiveView

**Files:**
- Create: `lib/web/live/gallery_live/index.ex`
- Create: `lib/web/live/gallery_live/index.html.heex`
- Create: `test/web/live/gallery_live/index_test.exs`

**Step 1: Write the failing tests**

Create `test/web/live/gallery_live/index_test.exs`:

```elixir
defmodule Web.GalleryLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Family.Galleries

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Summer 2025"})
    %{gallery: gallery}
  end

  test "lists all galleries", %{conn: conn, gallery: gallery} do
    {:ok, _view, html} = live(conn, ~p"/galleries")
    assert html =~ gallery.name
  end

  test "opens new gallery modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/galleries")
    refute has_element?(view, "#new-gallery-modal")
    view |> element("#open-new-gallery-btn") |> render_click()
    assert has_element?(view, "#new-gallery-modal")
  end

  test "creates a gallery via the new gallery modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/galleries")
    view |> element("#open-new-gallery-btn") |> render_click()

    view
    |> form("#new-gallery-form", gallery: %{name: "Winter 2025"})
    |> render_submit()

    assert has_element?(view, "[data-gallery-name]", "Winter 2025")
  end

  test "shows validation error for blank gallery name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/galleries")
    view |> element("#open-new-gallery-btn") |> render_click()

    view
    |> form("#new-gallery-form", gallery: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#new-gallery-form [data-error]")
  end

  test "deletes a gallery after confirmation", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries")

    view |> element("#delete-gallery-#{gallery.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-modal")

    view |> element("#confirm-delete-modal [phx-click='confirm_delete']") |> render_click()
    refute has_element?(view, "#gallery-#{gallery.id}")
  end
end
```

**Step 2: Run tests to verify failure**

```bash
mix test test/web/live/gallery_live/index_test.exs
```

Expected: FAIL — module not found.

**Step 3: Create the LiveView module**

Create `lib/web/live/gallery_live/index.ex`:

```elixir
defmodule Web.GalleryLive.Index do
  use Web, :live_view

  alias Family.Galleries
  alias Family.Galleries.Gallery

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_new_modal, false)
     |> assign(:confirm_delete_gallery, nil)
     |> assign(:form, to_form(Galleries.change_gallery(%Gallery{})))
     |> stream(:galleries, Galleries.list_galleries())}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_new_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_new_modal, true)
     |> assign(:form, to_form(Galleries.change_gallery(%Gallery{})))}
  end

  def handle_event("close_new_modal", _, socket) do
    {:noreply, assign(socket, :show_new_modal, false)}
  end

  def handle_event("validate_gallery", %{"gallery" => params}, socket) do
    changeset =
      %Gallery{}
      |> Galleries.change_gallery(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save_gallery", %{"gallery" => params}, socket) do
    case Galleries.create_gallery(params) do
      {:ok, gallery} ->
        {:noreply,
         socket
         |> assign(:show_new_modal, false)
         |> stream_insert(:galleries, gallery)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_gallery, Galleries.get_gallery!(id))}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete_gallery, nil)}
  end

  def handle_event("confirm_delete", _, socket) do
    gallery = socket.assigns.confirm_delete_gallery
    {:ok, _} = Galleries.delete_gallery(gallery)

    {:noreply,
     socket
     |> assign(:confirm_delete_gallery, nil)
     |> stream_delete(:galleries, gallery)}
  end
end
```

**Step 4: Create the template**

Create `lib/web/live/gallery_live/index.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 py-10">
    <div class="flex items-center justify-between mb-8">
      <h1 class="text-3xl font-bold tracking-tight text-base-content">Photo Galleries</h1>
      <button
        id="open-new-gallery-btn"
        phx-click="open_new_modal"
        class="btn btn-primary"
      >
        New Gallery
      </button>
    </div>

    <div id="galleries" phx-update="stream" class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-5">
      <div class="hidden only:block col-span-full text-center py-20 text-base-content/40">
        No galleries yet. Create your first one.
      </div>
      <div
        :for={{id, gallery} <- @streams.galleries}
        id={id}
        data-gallery-id={gallery.id}
        class="group relative card bg-base-100 shadow-sm border border-base-200 hover:shadow-md transition-all duration-200"
      >
        <.link navigate={~p"/galleries/#{gallery.id}"} class="block p-6">
          <div class="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <.icon name="hero-photo" class="w-6 h-6 text-primary" />
          </div>
          <h2 data-gallery-name class="text-lg font-semibold text-base-content truncate">
            {gallery.name}
          </h2>
          <p class="text-sm text-base-content/50 mt-1">
            {Calendar.strftime(gallery.inserted_at, "%B %d, %Y")}
          </p>
        </.link>
        <button
          id={"delete-gallery-#{gallery.id}"}
          phx-click="request_delete"
          phx-value-id={gallery.id}
          class="absolute top-3 right-3 p-1.5 rounded-lg text-base-content/30 hover:text-error hover:bg-error/10 opacity-0 group-hover:opacity-100 transition-all"
        >
          <.icon name="hero-trash" class="w-4 h-4" />
        </button>
      </div>
    </div>
  </div>

  <%!-- New Gallery Modal --%>
  <%= if @show_new_modal do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_new_modal"></div>
      <div id="new-gallery-modal" class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8">
        <h2 class="text-xl font-bold text-base-content mb-6">New Gallery</h2>
        <.form
          for={@form}
          id="new-gallery-form"
          phx-submit="save_gallery"
          phx-change="validate_gallery"
        >
          <.input field={@form[:name]} label="Gallery name" placeholder="e.g. Summer 2025" autofocus />
          <div class="flex gap-3 mt-6">
            <button type="submit" class="btn btn-primary flex-1">Create</button>
            <button type="button" phx-click="close_new_modal" class="btn btn-ghost flex-1">Cancel</button>
          </div>
        </.form>
      </div>
    </div>
  <% end %>

  <%!-- Delete Confirmation Modal --%>
  <%= if @confirm_delete_gallery do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete"></div>
      <div id="confirm-delete-modal" class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8">
        <h2 class="text-xl font-bold text-base-content mb-2">Delete Gallery</h2>
        <p class="text-base-content/60 mb-6">
          Delete <span class="font-semibold">"{@confirm_delete_gallery.name}"</span>? All photos will be permanently removed. This cannot be undone.
        </p>
        <div class="flex gap-3">
          <button phx-click="confirm_delete" class="btn btn-error flex-1">Delete</button>
          <button phx-click="cancel_delete" class="btn btn-ghost flex-1">Cancel</button>
        </div>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

**Step 5: Run tests**

```bash
mix test test/web/live/gallery_live/index_test.exs
```

Expected: all tests pass.

**Step 6: Commit**

```bash
git add lib/web/live/gallery_live/ test/web/live/gallery_live/
git commit -m "Add Gallery index LiveView with new gallery modal and delete confirmation"
```

---

### Task 11: Gallery show LiveView — upload, grid, PubSub

**Files:**
- Create: `lib/web/live/gallery_live/show.ex`
- Create: `lib/web/live/gallery_live/show.html.heex`
- Create: `test/web/live/gallery_live/show_test.exs`

**Step 1: Write failing tests**

Create `test/web/live/gallery_live/show_test.exs`:

```elixir
defmodule Web.GalleryLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Family.Galleries

  setup do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery"})
    %{gallery: gallery}
  end

  test "shows gallery name and upload area", %{conn: conn, gallery: gallery} do
    {:ok, _view, html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert html =~ gallery.name
    assert html =~ "upload-area"
  end

  test "shows empty state when no photos", %{conn: conn, gallery: gallery} do
    {:ok, _view, html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert html =~ "No photos yet"
  end

  test "toggles between masonry and uniform grid", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert has_element?(view, "#photo-grid.masonry-grid")
    view |> element("#layout-toggle") |> render_click()
    assert has_element?(view, "#photo-grid.uniform-grid")
  end

  test "activates and cancels selection mode", %{conn: conn, gallery: gallery} do
    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")
    refute has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    assert has_element?(view, "#selection-bar")
    view |> element("#select-btn") |> render_click()
    refute has_element?(view, "#selection-bar")
  end

  test "shows photo_processed message updates photo in grid", %{conn: conn, gallery: gallery} do
    {:ok, photo} = Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/x.jpg",
      original_filename: "x.jpg",
      content_type: "image/jpeg"
    })

    {:ok, view, _html} = live(conn, ~p"/galleries/#{gallery.id}")
    assert has_element?(view, "#photos-#{photo.id}")

    {:ok, updated} = Galleries.update_photo_processed(photo, "original.jpg")
    send(view.pid, {:photo_processed, updated})
    assert has_element?(view, "#photos-#{photo.id}")
  end
end
```

**Step 2: Run tests to verify failure**

```bash
mix test test/web/live/gallery_live/show_test.exs
```

Expected: FAIL — module not found.

**Step 3: Create the LiveView module**

Create `lib/web/live/gallery_live/show.ex`:

```elixir
defmodule Web.GalleryLive.Show do
  use Web, :live_view

  alias Family.Galleries

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
     |> stream(:photos, Galleries.list_photos(id))
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp .gif .dng .nef .tiff .tif),
       max_entries: 10,
       max_file_size: 300 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_layout", _, socket) do
    new_layout = if socket.assigns.grid_layout == :masonry, do: :uniform, else: :masonry
    {:noreply, assign(socket, :grid_layout, new_layout)}
  end

  def handle_event("toggle_select_mode", _, socket) do
    {:noreply,
     socket
     |> assign(:selection_mode, !socket.assigns.selection_mode)
     |> assign(:selected_ids, MapSet.new())}
  end

  def handle_event("toggle_photo_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id),
        do: MapSet.delete(socket.assigns.selected_ids, id),
        else: MapSet.put(socket.assigns.selected_ids, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("upload_photos", _params, socket) do
    gallery = socket.assigns.gallery

    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = ext_from_content_type(entry.client_type)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)

        {:ok, photo} =
          Galleries.create_photo(%{
            gallery_id: gallery.id,
            original_path: dest_path,
            original_filename: entry.client_name,
            content_type: entry.client_type
          })

        Oban.insert!(Family.Workers.ProcessPhotoJob.new(%{photo_id: photo.id}))
        {:ok, photo}
      end)

    socket = Enum.reduce(uploaded, socket, &stream_insert(&2, :photos, &1))
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("request_delete_photos", _, socket) do
    {:noreply, assign(socket, :confirm_delete_photos, true)}
  end

  def handle_event("cancel_delete_photos", _, socket) do
    {:noreply, assign(socket, :confirm_delete_photos, false)}
  end

  def handle_event("confirm_delete_photos", _, socket) do
    socket =
      Enum.reduce(MapSet.to_list(socket.assigns.selected_ids), socket, fn id, acc ->
        photo = Galleries.get_photo!(id)
        {:ok, _} = Galleries.delete_photo(photo)
        stream_delete(acc, :photos, photo)
      end)

    {:noreply,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:confirm_delete_photos, false)}
  end

  def handle_event("open_lightbox", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_photo, Galleries.get_photo!(String.to_integer(id)))}
  end

  def handle_event("close_lightbox", _, socket) do
    {:noreply, assign(socket, :selected_photo, nil)}
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :selected_photo, nil)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply, navigate_lightbox(socket, :next)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply, navigate_lightbox(socket, :prev)}
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

  def handle_event("lightbox_select", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_photo, Galleries.get_photo!(String.to_integer(id)))}
  end

  @impl true
  def handle_info({:photo_processed, photo}, socket) do
    {:noreply, stream_insert(socket, :photos, photo)}
  end

  def handle_info({:photo_failed, photo}, socket) do
    {:noreply, stream_insert(socket, :photos, photo)}
  end

  defp navigate_lightbox(socket, direction) do
    current = socket.assigns.selected_photo
    photos = Galleries.list_photos(socket.assigns.gallery.id)
    idx = Enum.find_index(photos, &(&1.id == current.id)) || 0

    next_idx =
      case direction do
        :next -> min(idx + 1, length(photos) - 1)
        :prev -> max(idx - 1, 0)
      end

    assign(socket, :selected_photo, Enum.at(photos, next_idx))
  end

  defp ext_from_content_type("image/jpeg"), do: ".jpg"
  defp ext_from_content_type("image/jpg"), do: ".jpg"
  defp ext_from_content_type("image/png"), do: ".png"
  defp ext_from_content_type("image/webp"), do: ".webp"
  defp ext_from_content_type("image/gif"), do: ".gif"
  defp ext_from_content_type("image/x-adobe-dng"), do: ".dng"
  defp ext_from_content_type("image/x-nikon-nef"), do: ".nef"
  defp ext_from_content_type("image/tiff"), do: ".tiff"
  defp ext_from_content_type(_), do: ".jpg"
end
```

**Step 4: Create the template**

Create `lib/web/live/gallery_live/show.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 py-8">

    <%!-- Header --%>
    <div class="flex items-center justify-between mb-6">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/galleries"} class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors">
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">{@gallery.name}</h1>
      </div>
      <div class="flex items-center gap-2">
        <button
          id="layout-toggle"
          phx-click="toggle_layout"
          class="p-2 rounded-lg text-base-content/50 hover:text-base-content hover:bg-base-200 transition-colors"
          title={if @grid_layout == :masonry, do: "Switch to uniform grid", else: "Switch to masonry"}
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
      <div id="selection-bar" class="mb-4 flex items-center justify-between bg-base-content text-base-100 rounded-xl px-5 py-3">
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

    <%!-- Upload area --%>
    <form id="upload-form" phx-submit="upload_photos" phx-change="validate" class="mb-8">
      <div
        id="upload-area"
        phx-drop-target={@uploads.photos.ref}
        class="border-2 border-dashed border-base-300 hover:border-primary/50 rounded-2xl p-10 text-center transition-colors group"
      >
        <.live_file_input upload={@uploads.photos} class="hidden" />
        <.icon name="hero-cloud-arrow-up" class="w-14 h-14 text-base-content/20 group-hover:text-primary/40 mx-auto mb-3 transition-colors" />
        <p class="text-base-content/60 font-medium">Drag & drop photos here</p>
        <p class="text-base-content/30 text-sm my-2">or</p>
        <label
          for={@uploads.photos.ref}
          class="inline-block cursor-pointer px-4 py-2 bg-primary text-primary-content rounded-lg hover:bg-primary/90 transition-colors text-sm font-medium"
        >
          Select Files
        </label>
        <p class="text-base-content/30 text-xs mt-4">JPEG, PNG, WebP, GIF, DNG, NEF · Up to 300MB each · Max 10 at a time</p>
      </div>

      <%!-- Staged upload entries --%>
      <%= if @uploads.photos.entries != [] do %>
        <div class="mt-3 space-y-2">
          <%= for entry <- @uploads.photos.entries do %>
            <div class="flex items-center gap-3 bg-base-100 rounded-xl border border-base-200 px-4 py-3">
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">{entry.client_name}</p>
                <div class="mt-1.5 h-1.5 bg-base-200 rounded-full overflow-hidden">
                  <div
                    class="h-full bg-primary rounded-full transition-all duration-300"
                    style={"width: #{entry.progress}%"}
                  ></div>
                </div>
                <%= for err <- upload_errors(@uploads.photos, entry) do %>
                  <p class="text-xs text-error mt-1">{upload_error_to_string(err)}</p>
                <% end %>
              </div>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="p-1.5 rounded-lg text-base-content/30 hover:text-base-content hover:bg-base-200 transition-colors"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>
          <% end %>
          <button
            type="submit"
            class="w-full btn btn-primary"
          >
            Upload {length(@uploads.photos.entries)} photo(s)
          </button>
        </div>
      <% end %>
    </form>

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
      <div class="hidden only:block col-span-full text-center py-20 text-base-content/30">
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
            <div class="aspect-square flex items-center justify-center animate-pulse">
              <.icon name="hero-photo" class="w-8 h-8 text-base-content/20" />
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
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" />
            Download original
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
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete_photos"></div>
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

**Step 5: Add `upload_error_to_string/1` helper to `show.ex`**

Add as a private function at the bottom of `show.ex`:

```elixir
defp upload_error_to_string(:too_large), do: "File too large (max 300MB)"
defp upload_error_to_string(:not_accepted), do: "File type not supported"
defp upload_error_to_string(:too_many_files), do: "Too many files (max 10)"
defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
```

**Step 6: Run show tests**

```bash
mix test test/web/live/gallery_live/show_test.exs
```

Expected: all tests pass.

**Step 7: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

**Step 8: Run precommit checks**

```bash
mix precommit
```

Expected: compiles, formats, tests all pass.

**Step 9: Commit**

```bash
git add lib/web/live/gallery_live/show.ex lib/web/live/gallery_live/show.html.heex test/web/live/gallery_live/show_test.exs
git commit -m "Add Gallery show LiveView with upload, grid, selection mode, and lightbox"
```

---

### Task 12: Masonry CSS

**Files:**
- Modify: `assets/css/app.css`

**Step 1: Add masonry break-inside fix**

The Tailwind `columns-*` approach handles masonry layout, but we need to ensure items don't break across columns. Add to `app.css`:

```css
.masonry-grid > * {
  break-inside: avoid;
}
```

**Note:** Do NOT use `@apply` — write raw CSS only.

**Step 2: Verify the CSS is picked up**

```bash
mix assets.build
```

Expected: builds without error.

**Step 3: Commit**

```bash
git add assets/css/app.css
git commit -m "Add masonry grid CSS"
```

---

### Task 13: Final verification

**Step 1: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

**Step 2: Run precommit**

```bash
mix precommit
```

Expected: no warnings, no formatting issues, all tests pass.

**Step 3: Smoke test the app manually**

```bash
mix phx.server
```

Visit `http://localhost:4000/galleries` and verify:
- Gallery list page loads
- "New Gallery" modal opens and creates a gallery
- Gallery show page loads with upload area
- File drag & drop and file picker both work
- Progress bars appear during upload
- Photos appear in the grid as pending, then update to thumbnails after Oban processes them
- Layout toggle switches between masonry and uniform grid
- Selection mode, batch delete, and confirmation modal work
- Lightbox opens on thumbnail click, thumbnail strip navigation works, arrow keys navigate, Escape closes it
- Download link serves the original file
