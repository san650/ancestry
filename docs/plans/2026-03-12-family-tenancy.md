# Family Tenancy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a top-level Family entity as a tenant, rename the base module from `Family` to `Ancestry` and OTP app from `:family` to `:ancestry`, scope galleries under families with nested URLs, and add cover photo upload/processing.

**Architecture:** Create an `Ancestry.Families` context owning Family CRUD + cover photo logic. `Ancestry.Galleries` adds `family_id` scoping. Routes nest under `/families/:family_id/...`. Landing page becomes the family index. Cover photos processed via Oban + Waffle (same pattern as gallery photos).

**Tech Stack:** Phoenix 1.8 + LiveView 1.1, Ecto/PostgreSQL, Oban, Waffle + ImageMagick, Tailwind CSS v4, PubSub

---

### Task 1: Rename OTP App and Base Module

This task renames all occurrences of the `:family` OTP app to `:ancestry` and the `Family` module namespace to `Ancestry`. The `Web` namespace stays unchanged.

**Files to modify (every file in the project):**

**Step 1: Rename `mix.exs`**

- `mix.exs:6` — `app: :family` → `app: :ancestry`
- `mix.exs:24` — `mod: {Family.Application, []}` → `mod: {Ancestry.Application, []}`
- `mix.exs:51` — `family:` esbuild profile key → `ancestry:`
- `mix.exs:53` — esbuild args referencing `family` profile
- `mix.exs:61` — `family:` tailwind profile key → `ancestry:`
- `mix.exs:90` — `"ecto.setup"` alias: seeds path stays same
- `mix.exs:94` — `"assets.build"` alias: `tailwind family` → `tailwind ancestry`, `esbuild family` → `esbuild ancestry`
- `mix.exs:96-98` — `"assets.deploy"` alias: same rename
- `mix.exs:106` — usage_rules `file:` stays `"CLAUDE.md"`

```elixir
# mix.exs top-level changes
defmodule Ancestry.MixProject do
  # ...
  app: :ancestry,
  # ...
  mod: {Ancestry.Application, []},
```

**Step 2: Rename all config files**

Every `config :family` → `config :ancestry`. Every `Family.Repo` → `Ancestry.Repo`. Every `Family.PubSub` → `Ancestry.PubSub`. Every `Family.Mailer` → `Ancestry.Mailer`.

- `config/config.exs` — Lines 10-11, 15, 22, 32, 38-40, 51, 61 (all `:family` → `:ancestry`, `Family.*` → `Ancestry.*`). Also rename esbuild/tailwind profile keys `family:` → `ancestry:`.
- `config/dev.exs` — Lines 4, 8 (`family_dev` → `ancestry_dev`), 19, 28-29 (esbuild/tailwind `:family` → `:ancestry`), 34 (`:family` → `:ancestry`), 56, 71
- `config/test.exs` — Lines 8, 12 (`family_test` → `ancestry_test`), 18, 24, 43-45, 47, 49, 51
- `config/prod.exs` — Lines 8, 13
- `config/runtime.exs` — Lines 15, 19-20, 24, 37, 59, 61, 77, 99, 109

**Step 3: Rename lib/ source files**

Move directories:
- `lib/family/` → `lib/ancestry/`
- `lib/family.ex` → `lib/ancestry.ex`

Rename modules in each file:
- `lib/ancestry.ex` — `defmodule Ancestry do` (was `Family`)
- `lib/ancestry/application.ex` — `defmodule Ancestry.Application do`, all `Family.*` refs → `Ancestry.*`
- `lib/ancestry/repo.ex` — `defmodule Ancestry.Repo do`, `otp_app: :ancestry`
- `lib/ancestry/mailer.ex` — `defmodule Ancestry.Mailer do`, `otp_app: :ancestry`
- `lib/ancestry/galleries.ex` — `defmodule Ancestry.Galleries do`, all `Family.*` refs → `Ancestry.*`
- `lib/ancestry/galleries/gallery.ex` — `defmodule Ancestry.Galleries.Gallery do`, `Family.*` → `Ancestry.*`
- `lib/ancestry/galleries/photo.ex` — `defmodule Ancestry.Galleries.Photo do`, `Family.*` → `Ancestry.*`
- `lib/ancestry/uploaders/photo.ex` — `defmodule Ancestry.Uploaders.Photo do`
- `lib/ancestry/workers/process_photo_job.ex` — `defmodule Ancestry.Workers.ProcessPhotoJob do`, `Family.*` → `Ancestry.*`

Rename refs in Web layer (these files stay in `lib/web/` but reference `Family.*`):
- `lib/web.ex:55` — `Application.compile_env(:family, ...)` → `Application.compile_env(:ancestry, ...)`
- `lib/web/endpoint.ex:2` — `otp_app: :family` → `otp_app: :ancestry`
- `lib/web/endpoint.ex:9` — `_family_key` → `_ancestry_key`
- `lib/web/endpoint.ex:14` — `Application.compile_env(:family, ...)` → `Application.compile_env(:ancestry, ...)`
- `lib/web/endpoint.ex:29` — `from: :family` → `from: :ancestry`
- `lib/web/endpoint.ex:44` — `otp_app: :family` → `otp_app: :ancestry`
- `lib/web/router.ex:34` — `Application.compile_env(:family, :dev_routes)` → `Application.compile_env(:ancestry, :dev_routes)`
- `lib/web/live/gallery_live/index.ex` — `Family.Galleries` → `Ancestry.Galleries`
- `lib/web/live/gallery_live/show.ex` — `Family.Galleries` → `Ancestry.Galleries`, `Family.PubSub` → `Ancestry.PubSub`
- `lib/web/components/layouts.ex:55` — Update "Family" text to "Ancestry" in navbar logo
- `lib/web/controllers/page_html/home.html.heex` — Update welcome text
- `lib/web/live_acceptance.ex` — If it references `Family.Repo`, rename

**Step 4: Rename test files**

Move directories:
- `test/family/` → `test/ancestry/`

Rename modules in each file:
- `test/support/data_case.ex` — `defmodule Ancestry.DataCase do`, `Family.Repo` → `Ancestry.Repo`
- `test/support/conn_case.ex` — `Family.DataCase` → `Ancestry.DataCase`
- `test/ancestry/galleries_test.exs` — `defmodule Ancestry.GalleriesTest do`, `Family.*` → `Ancestry.*`
- `test/ancestry/workers/process_photo_job_test.exs` — `Family.*` → `Ancestry.*`
- `test/web/live/gallery_live/index_test.exs` — `Family.Galleries` → `Ancestry.Galleries`
- `test/web/live/gallery_live/show_test.exs` — `Family.Galleries` → `Ancestry.Galleries`
- `test/web/controllers/page_controller_test.exs` — Update welcome text assertion
- `test/support/e2e_case.ex` — If it references `Family.*`, rename

**Step 5: Run tests to verify rename**

Run: `mix test --exclude e2e`
Expected: All tests pass (E2E tests excluded since they need browser setup)

**Step 6: Commit**

```bash
git add -A
git commit -m "Rename base module from Family to Ancestry and OTP app to :ancestry"
```

---

### Task 2: Create Family Schema and Migration

**Files:**
- Create: `lib/ancestry/families/family.ex`
- Create: `priv/repo/migrations/*_create_families.exs` (use `mix ecto.gen.migration`)
- Modify: `priv/repo/seeds.exs`

**Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_families`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.CreateFamilies do
  use Ecto.Migration

  def change do
    create table(:families) do
      add :name, :text, null: false
      add :cover, :text
      add :cover_status, :text
      timestamps()
    end
  end
end
```

**Step 3: Write the Family schema**

Create `lib/ancestry/families/family.ex`:

```elixir
defmodule Ancestry.Families.Family do
  use Ecto.Schema
  import Ecto.Changeset

  schema "families" do
    field :name, :string
    field :cover, :string
    field :cover_status, :string
    has_many :galleries, Ancestry.Galleries.Gallery, on_delete: :delete_all
    timestamps()
  end

  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
```

**Step 4: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully

**Step 5: Commit**

```bash
git add lib/ancestry/families/family.ex priv/repo/migrations/*_create_families.exs
git commit -m "Add Family schema and migration"
```

---

### Task 3: Add family_id to Gallery and Update Associations

**Files:**
- Create: `priv/repo/migrations/*_add_family_id_to_galleries.exs`
- Modify: `lib/ancestry/galleries/gallery.ex`
- Modify: `lib/ancestry/galleries.ex`

**Step 1: Generate migration**

Run: `mix ecto.gen.migration add_family_id_to_galleries`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.AddFamilyIdToGalleries do
  use Ecto.Migration

  def change do
    alter table(:galleries) do
      add :family_id, references(:families, on_delete: :delete_all), null: false
    end

    create index(:galleries, [:family_id])
  end
end
```

**Step 3: Update Gallery schema**

Modify `lib/ancestry/galleries/gallery.ex`:

```elixir
defmodule Ancestry.Galleries.Gallery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "galleries" do
    field :name, :string
    belongs_to :family, Ancestry.Families.Family
    has_many :photos, Ancestry.Galleries.Photo, on_delete: :delete_all
    timestamps()
  end

  def changeset(gallery, attrs) do
    gallery
    |> cast(attrs, [:name, :family_id])
    |> validate_required([:name, :family_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:family_id)
  end
end
```

**Step 4: Update Galleries context — scope by family_id**

Modify `lib/ancestry/galleries.ex`:

Change `list_galleries/0` to `list_galleries/1`:

```elixir
def list_galleries(family_id) do
  Repo.all(from g in Gallery, where: g.family_id == ^family_id, order_by: [asc: g.inserted_at])
end
```

Change `create_gallery/1` — no change needed, `family_id` is now cast in the changeset.

**Step 5: Update seeds**

Modify `priv/repo/seeds.exs`:

```elixir
alias Ancestry.Repo
alias Ancestry.Families.Family

# Create default family
%Family{name: "My Family"}
|> Repo.insert!(on_conflict: :nothing)
```

**Step 6: Run migration and seeds**

Run: `mix ecto.migrate && mix run priv/repo/seeds.exs`
Expected: Both succeed

**Step 7: Commit**

```bash
git add lib/ancestry/galleries/gallery.ex lib/ancestry/galleries.ex priv/repo/migrations/*_add_family_id_to_galleries.exs priv/repo/seeds.exs
git commit -m "Add family_id to galleries and scope gallery queries by family"
```

---

### Task 4: Create Families Context with Tests

**Files:**
- Create: `lib/ancestry/families.ex`
- Create: `test/ancestry/families_test.exs`

**Step 1: Write the failing test**

Create `test/ancestry/families_test.exs`:

```elixir
defmodule Ancestry.FamiliesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.Families.Family

  describe "families" do
    test "list_families/0 returns all families ordered by name" do
      f1 = family_fixture(%{name: "Beta"})
      f2 = family_fixture(%{name: "Alpha"})
      assert Families.list_families() == [f2, f1]
    end

    test "get_family!/1 returns the family with given id" do
      family = family_fixture()
      assert Families.get_family!(family.id) == family
    end

    test "create_family/1 with valid data creates a family" do
      assert {:ok, %Family{} = family} = Families.create_family(%{name: "The Smiths"})
      assert family.name == "The Smiths"
    end

    test "create_family/1 with blank name returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Families.create_family(%{name: ""})
    end

    test "update_family/2 updates the family name" do
      family = family_fixture()
      assert {:ok, %Family{} = updated} = Families.update_family(family, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "delete_family!/1 deletes the family" do
      family = family_fixture()
      assert {:ok, %Family{}} = Families.delete_family(family)
      assert_raise Ecto.NoResultsError, fn -> Families.get_family!(family.id) end
    end

    test "change_family/2 returns a family changeset" do
      family = family_fixture()
      assert %Ecto.Changeset{} = Families.change_family(family)
    end
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Families.create_family()

    family
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/families_test.exs`
Expected: FAIL — `Ancestry.Families` module doesn't exist

**Step 3: Write the Families context**

Create `lib/ancestry/families.ex`:

```elixir
defmodule Ancestry.Families do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Families.Family

  def list_families do
    Repo.all(from f in Family, order_by: [asc: f.name])
  end

  def get_family!(id), do: Repo.get!(Family, id)

  def create_family(attrs \\ %{}) do
    %Family{}
    |> Family.changeset(attrs)
    |> Repo.insert()
  end

  def update_family(%Family{} = family, attrs) do
    family
    |> Family.changeset(attrs)
    |> Repo.update()
  end

  def delete_family(%Family{} = family) do
    # Clean up files on disk
    cleanup_family_files(family)
    Repo.delete(family)
  end

  def change_family(%Family{} = family, attrs \\ %{}) do
    Family.changeset(family, attrs)
  end

  defp cleanup_family_files(family) do
    # Remove cover photo files
    cover_dir = Path.join(["priv", "static", "uploads", "families", "#{family.id}"])
    File.rm_rf(cover_dir)

    # Remove all gallery photo files scoped under this family
    photos_dir = Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
    File.rm_rf(photos_dir)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/families_test.exs`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/ancestry/families.ex test/ancestry/families_test.exs
git commit -m "Add Families context with CRUD operations and tests"
```

---

### Task 5: Update Galleries Tests for family_id Requirement

**Files:**
- Modify: `test/ancestry/galleries_test.exs`
- Modify: `test/ancestry/workers/process_photo_job_test.exs`
- Modify: `test/web/live/gallery_live/index_test.exs`
- Modify: `test/web/live/gallery_live/show_test.exs`

All gallery creation now requires a `family_id`. Update every test that creates a gallery to first create a family.

**Step 1: Update galleries_test.exs**

Add a family fixture and pass `family_id` to all gallery creation calls:

```elixir
defmodule Ancestry.GalleriesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.Galleries.Gallery

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  describe "galleries" do
    test "list_galleries/1 returns all galleries for a family ordered by inserted_at", %{family: family} do
      g1 = gallery_fixture(%{name: "Alpha", family_id: family.id})
      g2 = gallery_fixture(%{name: "Beta", family_id: family.id})
      assert Galleries.list_galleries(family.id) == [g1, g2]
    end

    test "get_gallery!/1 returns the gallery with given id", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert Galleries.get_gallery!(gallery.id) == gallery
    end

    test "create_gallery/1 with valid data creates a gallery", %{family: family} do
      assert {:ok, %Gallery{} = gallery} = Galleries.create_gallery(%{name: "Vacation 2025", family_id: family.id})
      assert gallery.name == "Vacation 2025"
      assert gallery.family_id == family.id
    end

    test "create_gallery/1 with blank name returns error changeset", %{family: family} do
      assert {:error, %Ecto.Changeset{}} = Galleries.create_gallery(%{name: "", family_id: family.id})
    end

    test "delete_gallery/1 deletes the gallery", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert {:ok, %Gallery{}} = Galleries.delete_gallery(gallery)
      assert_raise Ecto.NoResultsError, fn -> Galleries.get_gallery!(gallery.id) end
    end

    test "change_gallery/2 returns a gallery changeset", %{family: family} do
      gallery = gallery_fixture(%{family_id: family.id})
      assert %Ecto.Changeset{} = Galleries.change_gallery(gallery)
    end
  end

  # ... photo tests also need family_id in gallery creation setup ...
  # Update the photos describe block setup:
  # setup do
  #   {:ok, family} = Families.create_family(%{name: "Test Family"})
  #   {:ok, gallery} = Galleries.create_gallery(%{name: "Test", family_id: family.id})
  #   %{gallery: gallery}
  # end

  defp gallery_fixture(attrs \\ %{}) do
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery"})
      |> Galleries.create_gallery()

    gallery
  end
end
```

**Step 2: Update process_photo_job_test.exs**

Add family creation in setup block:

```elixir
# In setup block, before creating the gallery:
{:ok, family} = Ancestry.Families.create_family(%{name: "Test Family"})
{:ok, gallery} = Ancestry.Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})
```

**Step 3: Update LiveView test files**

In `test/web/live/gallery_live/index_test.exs` and `show_test.exs`, update setup blocks to create a family first and pass `family_id`. Also update all route paths from `~p"/galleries"` to `~p"/families/#{family.id}/galleries"` (and similar for show).

For index_test.exs:
```elixir
setup do
  {:ok, family} = Ancestry.Families.create_family(%{name: "Test Family"})
  {:ok, gallery} = Ancestry.Galleries.create_gallery(%{name: "Summer 2025", family_id: family.id})
  %{family: family, gallery: gallery}
end

# All routes: ~p"/galleries" → ~p"/families/#{family.id}/galleries"
```

For show_test.exs:
```elixir
setup do
  {:ok, family} = Ancestry.Families.create_family(%{name: "Test Family"})
  {:ok, gallery} = Ancestry.Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})
  %{family: family, gallery: gallery}
end

# All routes: ~p"/galleries/#{gallery.id}" → ~p"/families/#{family.id}/galleries/#{gallery.id}"
```

**Step 4: Run all tests**

Run: `mix test --exclude e2e`
Expected: Tests will fail until routes are updated (Task 6). That's OK — we commit the test updates now.

**Step 5: Commit**

```bash
git add test/
git commit -m "Update all tests to require family_id for gallery creation"
```

---

### Task 6: Update Router for Nested Family/Gallery Routes

**Files:**
- Modify: `lib/web/router.ex`
- Remove: `lib/web/controllers/page_controller.ex`
- Remove: `lib/web/controllers/page_html.ex`
- Remove: `lib/web/controllers/page_html/home.html.heex`

**Step 1: Update the router**

Replace the existing routes with nested family/gallery routes. The landing page `/` becomes `FamilyLive.Index`:

```elixir
defmodule Web.Router do
  use Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Web do
    pipe_through :browser

    live_session :default do
      live "/", FamilyLive.Index, :index
      live "/families/new", FamilyLive.New, :new
      live "/families/:family_id", FamilyLive.Show, :show
      live "/families/:family_id/galleries", GalleryLive.Index, :index
      live "/families/:family_id/galleries/:id", GalleryLive.Show, :show
    end
  end

  if Application.compile_env(:ancestry, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Web.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
```

**Step 2: Remove old PageController files**

Delete:
- `lib/web/controllers/page_controller.ex`
- `lib/web/controllers/page_html.ex`
- `lib/web/controllers/page_html/home.html.heex`

**Step 3: Update page controller test**

Replace `test/web/controllers/page_controller_test.exs` with a family landing page test (or delete it since FamilyLive.Index tests will cover this — delete it for now, it will be covered by FamilyLive tests).

**Step 4: Commit**

```bash
git add lib/web/router.ex test/web/controllers/
git rm lib/web/controllers/page_controller.ex lib/web/controllers/page_html.ex lib/web/controllers/page_html/home.html.heex
git commit -m "Update router with nested family/gallery routes, remove PageController"
```

---

### Task 7: Create FamilyLive.Index (Landing Page)

**Files:**
- Create: `lib/web/live/family_live/index.ex`
- Create: `lib/web/live/family_live/index.html.heex`
- Create: `test/web/live/family_live/index_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/family_live/index_test.exs`:

```elixir
defmodule Web.FamilyLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  test "lists all families", %{conn: conn} do
    {:ok, family} = Families.create_family(%{name: "The Smiths"})
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ family.name
  end

  test "navigates to new family page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#new-family-btn") |> render_click()
    assert_patch(view, ~p"/families/new")
  end

  test "shows empty state when no families", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "No families yet"
  end

  test "deletes a family after confirmation", %{conn: conn} do
    {:ok, family} = Families.create_family(%{name: "To Delete"})
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#delete-family-#{family.id}") |> render_click()
    assert has_element?(view, "#confirm-delete-family-modal")

    view |> element("#confirm-delete-family-modal [phx-click='confirm_delete']") |> render_click()
    refute has_element?(view, "#family-#{family.id}")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/family_live/index_test.exs`
Expected: FAIL — module doesn't exist

**Step 3: Write the LiveView module**

Create `lib/web/live/family_live/index.ex`:

```elixir
defmodule Web.FamilyLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Families.Family

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:confirm_delete_family, nil)
     |> stream(:families, Families.list_families())}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("request_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_family, Families.get_family!(id))}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete_family, nil)}
  end

  def handle_event("confirm_delete", _, socket) do
    family = socket.assigns.confirm_delete_family
    {:ok, _} = Families.delete_family(family)

    {:noreply,
     socket
     |> assign(:confirm_delete_family, nil)
     |> stream_delete(:families, family)}
  end
end
```

**Step 4: Write the template**

Create `lib/web/live/family_live/index.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <h1 class="text-lg font-semibold">Families</h1>
      <.link navigate={~p"/families/new"} id="new-family-btn" class="btn btn-primary btn-sm">
        <.icon name="hero-plus" class="size-4" /> New Family
      </.link>
    </div>
  </:toolbar>

  <div class="max-w-7xl mx-auto">
    <div id="families" phx-update="stream" class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
      <div class="hidden only:block text-center py-12 text-base-content/60" id="families-empty">
        No families yet
      </div>
      <div :for={{id, family} <- @streams.families} id={id} class="group relative">
        <.link navigate={~p"/families/#{family.id}/galleries"} class="block">
          <div class="card bg-base-200 shadow-sm hover:shadow-md transition-shadow overflow-hidden">
            <figure class="aspect-[4/3] bg-base-300 flex items-center justify-center">
              <%= if family.cover && family.cover_status == "processed" do %>
                <img
                  src={~p"/uploads/families/#{family.id}/cover.jpg"}
                  class="w-full h-full object-cover"
                  alt={family.name}
                />
              <% else %>
                <.icon name="hero-users" class="size-16 text-base-content/20" />
              <% end %>
            </figure>
            <div class="card-body p-4">
              <h2 class="card-title text-base" data-family-name>{family.name}</h2>
            </div>
          </div>
        </.link>

        <button
          id={"delete-family-#{family.id}"}
          phx-click="request_delete"
          phx-value-id={family.id}
          class={[
            "absolute top-2 right-2 btn btn-circle btn-xs btn-error",
            "opacity-0 group-hover:opacity-100 transition-opacity"
          ]}
        >
          <.icon name="hero-trash" class="size-3.5" />
        </button>
      </div>
    </div>
  </div>

  <%= if @confirm_delete_family do %>
    <div id="confirm-delete-family-modal" class="modal modal-open" phx-window-keydown="cancel_delete" phx-key="Escape">
      <div class="modal-box">
        <h3 class="font-bold text-lg">Delete family?</h3>
        <p class="py-4">
          Are you sure you want to delete <strong>{@confirm_delete_family.name}</strong>?
          This will permanently delete all galleries, photos, and files.
        </p>
        <div class="modal-action">
          <button class="btn" phx-click="cancel_delete">Cancel</button>
          <button class="btn btn-error" phx-click="confirm_delete">Delete</button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="cancel_delete"></div>
    </div>
  <% end %>
</Layouts.app>
```

**Step 5: Run tests**

Run: `mix test test/web/live/family_live/index_test.exs`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add lib/web/live/family_live/ test/web/live/family_live/
git commit -m "Add FamilyLive.Index as the landing page with family grid"
```

---

### Task 8: Create FamilyLive.New (Create Family Page)

**Files:**
- Create: `lib/web/live/family_live/new.ex`
- Create: `lib/web/live/family_live/new.html.heex`
- Create: `test/web/live/family_live/new_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/family_live/new_test.exs`:

```elixir
defmodule Web.FamilyLive.NewTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  test "renders new family form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/families/new")
    assert html =~ "New Family"
    assert html =~ "new-family-form"
  end

  test "creates a family with valid name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/families/new")

    view
    |> form("#new-family-form", family: %{name: "The Johnsons"})
    |> render_submit()

    [family] = Families.list_families()
    assert family.name == "The Johnsons"
    assert_redirect(view, ~p"/families/#{family.id}/galleries")
  end

  test "shows validation error for blank name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/families/new")

    view
    |> form("#new-family-form", family: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#new-family-form .text-error")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/family_live/new_test.exs`
Expected: FAIL

**Step 3: Write the LiveView**

Create `lib/web/live/family_live/new.ex`:

```elixir
defmodule Web.FamilyLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.Families.Family

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(Families.change_family(%Family{})))
     |> allow_upload(:cover,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_event("validate", %{"family" => params}, socket) do
    changeset =
      %Family{}
      |> Families.change_family(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"family" => params}, socket) do
    case Families.create_family(params) do
      {:ok, family} ->
        socket = maybe_process_cover(socket, family)
        {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}/galleries")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :cover, ref)}
  end

  defp maybe_process_cover(socket, family) do
    case uploaded_entries(socket, :cover) do
      {[_entry], []} ->
        consume_uploaded_entries(socket, :cover, fn %{path: tmp_path}, entry ->
          ext = Path.extname(entry.client_name) |> String.downcase()
          uuid = Ecto.UUID.generate()
          dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
          File.mkdir_p!(dest_dir)
          dest_path = Path.join(dest_dir, "cover#{ext}")
          File.cp!(tmp_path, dest_path)

          Ancestry.Families.update_cover_pending(family, dest_path)
          {:ok, :uploaded}
        end)

        socket

      _ ->
        socket
    end
  end
end
```

**Step 4: Write the template**

Create `lib/web/live/family_live/new.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <div class="flex items-center gap-3">
        <.link navigate={~p"/"} class="btn btn-ghost btn-sm btn-circle">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <h1 class="text-lg font-semibold">New Family</h1>
      </div>
    </div>
  </:toolbar>

  <div class="max-w-lg mx-auto py-8">
    <.form for={@form} id="new-family-form" phx-change="validate" phx-submit="save" class="space-y-6">
      <.input field={@form[:name]} type="text" label="Family name" placeholder="e.g. The Smiths" autofocus />

      <div>
        <label class="label">
          <span class="label-text">Cover photo (optional)</span>
        </label>
        <div class="flex items-center gap-4">
          <.live_file_input upload={@uploads.cover} class="file-input file-input-bordered w-full" />
        </div>
        <%= for entry <- @uploads.cover.entries do %>
          <div class="flex items-center gap-2 mt-2">
            <.live_img_preview entry={entry} class="w-20 h-14 object-cover rounded" />
            <span class="text-sm flex-1 truncate">{entry.client_name}</span>
            <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="btn btn-ghost btn-xs">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <%= for err <- upload_errors(@uploads.cover, entry) do %>
            <p class="text-error text-sm mt-1">{upload_error_to_string(err)}</p>
          <% end %>
        <% end %>
      </div>

      <div class="flex justify-end gap-3">
        <.link navigate={~p"/"} class="btn">Cancel</.link>
        <button type="submit" class="btn btn-primary">Create Family</button>
      </div>
    </.form>
  </div>
</Layouts.app>
```

Note: Add the `upload_error_to_string/1` helper to the module:

```elixir
defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
defp upload_error_to_string(:not_accepted), do: "File type not supported"
defp upload_error_to_string(:too_many_files), do: "Only one cover photo allowed"
defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
```

**Step 5: Add `update_cover_pending/2` to Families context**

Add to `lib/ancestry/families.ex`:

```elixir
def update_cover_pending(%Family{} = family, original_path) do
  family
  |> Ecto.Changeset.change(%{cover_status: "pending"})
  |> Repo.update!()

  Oban.insert(Ancestry.Workers.ProcessFamilyCoverJob.new(%{
    family_id: family.id,
    original_path: original_path
  }))
end
```

**Step 6: Run tests**

Run: `mix test test/web/live/family_live/new_test.exs`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add lib/web/live/family_live/new.ex lib/web/live/family_live/new.html.heex test/web/live/family_live/new_test.exs lib/ancestry/families.ex
git commit -m "Add FamilyLive.New page for creating families with optional cover photo"
```

---

### Task 9: Create FamilyLive.Show (Edit/Delete Family)

**Files:**
- Create: `lib/web/live/family_live/show.ex`
- Create: `lib/web/live/family_live/show.html.heex`
- Create: `test/web/live/family_live/show_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/family_live/show_test.exs`:

```elixir
defmodule Web.FamilyLive.ShowTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Ancestry.Families

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    %{family: family}
  end

  test "shows family name", %{conn: conn, family: family} do
    {:ok, _view, html} = live(conn, ~p"/families/#{family.id}")
    assert html =~ family.name
  end

  test "updates family name", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}")

    view |> element("#edit-family-btn") |> render_click()

    view
    |> form("#edit-family-form", family: %{name: "Updated Name"})
    |> render_submit()

    assert render(view) =~ "Updated Name"
  end

  test "deletes family and redirects to index", %{conn: conn, family: family} do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}")

    view |> element("#delete-family-btn") |> render_click()
    assert has_element?(view, "#confirm-delete-family-modal")

    view |> element("#confirm-delete-family-modal [phx-click='confirm_delete']") |> render_click()
    assert_redirect(view, ~p"/")
  end
end
```

**Step 2: Write the LiveView and template**

Create `lib/web/live/family_live/show.ex` with mount, handle_params, and event handlers for edit/delete.

Create `lib/web/live/family_live/show.html.heex` with family detail view, edit form modal, and delete confirmation modal.

The show page should display:
- Family name with edit button
- Cover photo (or fallback) with option to upload/replace
- Delete button
- Link to galleries

**Step 3: Run tests**

Run: `mix test test/web/live/family_live/show_test.exs`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex test/web/live/family_live/show_test.exs
git commit -m "Add FamilyLive.Show page for viewing, editing, and deleting families"
```

---

### Task 10: Update GalleryLive.Index for Family Scoping

**Files:**
- Modify: `lib/web/live/gallery_live/index.ex`
- Modify: `lib/web/live/gallery_live/index.html.heex`

**Step 1: Update the LiveView**

Modify `lib/web/live/gallery_live/index.ex`:

- `mount/3` now receives `%{"family_id" => family_id}` in params
- Fetch family via `Families.get_family!(family_id)`
- Assign `:family` to socket
- Scope `list_galleries(family_id)` and `create_gallery` passes `family_id`

Key changes:

```elixir
def mount(%{"family_id" => family_id}, _session, socket) do
  family = Ancestry.Families.get_family!(family_id)

  {:ok,
   socket
   |> assign(:family, family)
   |> assign(:show_new_modal, false)
   |> assign(:confirm_delete_gallery, nil)
   |> assign(:form, to_form(Ancestry.Galleries.change_gallery(%Ancestry.Galleries.Gallery{})))
   |> stream(:galleries, Ancestry.Galleries.list_galleries(family_id))}
end

def handle_event("save_gallery", %{"gallery" => params}, socket) do
  params = Map.put(params, "family_id", socket.assigns.family.id)
  # ... rest of save logic
end
```

**Step 2: Update the template**

Modify `lib/web/live/gallery_live/index.html.heex`:

- Back button links to `~p"/"`
- Show family name in toolbar: "Family Name — Galleries"
- Gallery card links to `~p"/families/#{@family.id}/galleries/#{gallery.id}"`
- Title references the family

**Step 3: Run tests**

Run: `mix test test/web/live/gallery_live/index_test.exs`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add lib/web/live/gallery_live/index.ex lib/web/live/gallery_live/index.html.heex
git commit -m "Scope GalleryLive.Index under family with family_id from route"
```

---

### Task 11: Update GalleryLive.Show for Family Scoping

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex`
- Modify: `lib/web/live/gallery_live/show.html.heex`

**Step 1: Update the LiveView**

Modify `lib/web/live/gallery_live/show.ex`:

- `mount/3` now receives `%{"family_id" => family_id, "id" => id}` in params
- Fetch and assign `:family`
- Back button navigates to `~p"/families/#{family_id}/galleries"`

```elixir
def mount(%{"family_id" => family_id, "id" => id}, _session, socket) do
  family = Ancestry.Families.get_family!(family_id)
  gallery = Ancestry.Galleries.get_gallery!(id)
  # ... rest of mount
  socket
  |> assign(:family, family)
  |> assign(:gallery, gallery)
  # ...
end
```

**Step 2: Update the template**

- Back link: `~p"/families/#{@family.id}/galleries"`
- No other major changes needed

**Step 3: Run tests**

Run: `mix test test/web/live/gallery_live/show_test.exs`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add lib/web/live/gallery_live/show.ex lib/web/live/gallery_live/show.html.heex
git commit -m "Scope GalleryLive.Show under family with family_id from route"
```

---

### Task 12: Update Photo Storage Path to Include family_id

**Files:**
- Modify: `lib/ancestry/uploaders/photo.ex`

**Step 1: Update the storage_dir function**

Modify `lib/ancestry/uploaders/photo.ex:37-39`:

The photo scope needs `family_id` available. Since `photo.gallery` association holds the `family_id`, we need to preload it or pass it differently. The simplest approach: add a `family_id` field access on the photo's gallery association.

Actually, the Waffle uploader receives `{file, scope}` where scope is the photo struct. We need to ensure the photo struct has `family_id` accessible. Options:
1. Preload the gallery association on the photo before calling Waffle
2. Add `family_id` directly to the photo record

Option 2 is simpler but adds redundancy. Option 1 is cleaner. Since `ProcessPhotoJob` fetches the photo, we can preload there.

Update `storage_dir`:

```elixir
def storage_dir(_version, {_file, scope}) do
  "uploads/photos/#{scope.gallery.family_id}/#{scope.gallery_id}/#{scope.id}"
end
```

**Step 2: Update ProcessPhotoJob to preload gallery**

Modify `lib/ancestry/workers/process_photo_job.ex`:

```elixir
def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
  photo = Galleries.get_photo!(photo_id) |> Ancestry.Repo.preload(:gallery)
  # ... rest same
end
```

Also update `process_photo/1` to pass the preloaded photo to Waffle.

**Step 3: Run existing tests**

Run: `mix test --exclude e2e`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add lib/ancestry/uploaders/photo.ex lib/ancestry/workers/process_photo_job.ex
git commit -m "Update photo storage path to include family_id"
```

---

### Task 13: Create FamilyCover Waffle Uploader and Oban Worker

**Files:**
- Create: `lib/ancestry/uploaders/family_cover.ex`
- Create: `lib/ancestry/workers/process_family_cover_job.ex`
- Create: `test/ancestry/workers/process_family_cover_job_test.exs`

**Step 1: Write the failing test**

Create `test/ancestry/workers/process_family_cover_job_test.exs`:

```elixir
defmodule Ancestry.Workers.ProcessFamilyCoverJobTest do
  use Ancestry.DataCase, async: false
  use Oban.Testing, repo: Ancestry.Repo

  alias Ancestry.Families
  alias Ancestry.Workers.ProcessFamilyCoverJob

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    # Copy test image to a temp location
    tmp_dir = Path.join(System.tmp_dir!(), "cover_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    src = Path.join(["test", "fixtures", "test_image.jpg"])
    dest = Path.join(tmp_dir, "cover.jpg")
    File.cp!(src, dest)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{family: family, tmp_path: dest}
  end

  test "processes cover photo and updates family status", %{family: family, tmp_path: tmp_path} do
    assert :ok = perform_job(ProcessFamilyCoverJob, %{family_id: family.id, original_path: tmp_path})

    updated = Families.get_family!(family.id)
    assert updated.cover_status == "processed"
  end

  test "marks cover as failed when original_path is missing", %{family: family} do
    assert {:error, _} = ProcessFamilyCoverJob.perform(
      %Oban.Job{args: %{"family_id" => family.id, "original_path" => "/nonexistent/cover.jpg"}}
    )

    updated = Families.get_family!(family.id)
    assert updated.cover_status == "failed"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/workers/process_family_cover_job_test.exs`
Expected: FAIL

**Step 3: Write the Waffle uploader**

Create `lib/ancestry/uploaders/family_cover.ex`:

```elixir
defmodule Ancestry.Uploaders.FamilyCover do
  use Waffle.Definition

  @versions [:cover]
  @valid_extensions ~w(.jpg .jpeg .png .webp)

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  def transform(:cover, _) do
    {:convert, "-resize 1200x800> -auto-orient -strip -quality 85", :jpg}
  end

  def filename(:cover, _), do: "cover"

  def storage_dir(_version, {_file, scope}) do
    "uploads/families/#{scope.id}"
  end
end
```

**Step 4: Write the Oban worker**

Create `lib/ancestry/workers/process_family_cover_job.ex`:

```elixir
defmodule Ancestry.Workers.ProcessFamilyCoverJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.Families
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"family_id" => family_id, "original_path" => original_path}}) do
    family = Families.get_family!(family_id)

    case process_cover(family, original_path) do
      {:ok, updated_family} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "family:#{family.id}",
          {:cover_processed, updated_family}
        )

        :ok

      {:error, reason} ->
        Families.update_cover_failed(family)

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "family:#{family.id}",
          {:cover_failed, family}
        )

        {:error, reason}
    end
  end

  defp process_cover(family, original_path) do
    waffle_file = %{
      filename: Path.basename(original_path),
      path: original_path
    }

    case Uploaders.FamilyCover.store({waffle_file, family}) do
      {:ok, _filename} -> Families.update_cover_processed(family)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Step 5: Add helper functions to Families context**

Add to `lib/ancestry/families.ex`:

```elixir
def update_cover_processed(%Family{} = family) do
  family
  |> Ecto.Changeset.change(%{cover_status: "processed"})
  |> Repo.update()
end

def update_cover_failed(%Family{} = family) do
  family
  |> Ecto.Changeset.change(%{cover_status: "failed"})
  |> Repo.update()
end
```

**Step 6: Run tests**

Run: `mix test test/ancestry/workers/process_family_cover_job_test.exs`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add lib/ancestry/uploaders/family_cover.ex lib/ancestry/workers/process_family_cover_job.ex test/ancestry/workers/process_family_cover_job_test.exs lib/ancestry/families.ex
git commit -m "Add FamilyCover Waffle uploader and ProcessFamilyCoverJob Oban worker"
```

---

### Task 14: Update Layouts and Navigation

**Files:**
- Modify: `lib/web/components/layouts.ex`

**Step 1: Update the app layout navbar**

The navbar should link to `/` (families index) instead of `/galleries`. Update the logo text from "Family" to "Ancestry":

```elixir
# In the app/1 function template:
<header class="navbar px-4 sm:px-6 lg:px-8">
  <div class="flex-1">
    <a href="/" class="flex-1 flex w-fit items-center gap-2">
      <img src={~p"/images/logo.png"} width="36" />
      <span class="text-sm font-semibold">Ancestry</span>
    </a>
  </div>
  <div class="flex-none">
    <ul class="flex flex-column px-1 space-x-4 items-center">
      <li>
        <.link href={~p"/"}>Families</.link>
      </li>
    </ul>
  </div>
</header>
```

**Step 2: Commit**

```bash
git add lib/web/components/layouts.ex
git commit -m "Update layout navbar to link to families index"
```

---

### Task 15: Update E2E Tests

**Files:**
- Modify: `test/web/e2e/gallery_navigation_test.exs`
- Modify: `test/web/e2e/gallery_upload_test.exs`
- Modify: `test/support/e2e_case.ex`

**Step 1: Update E2E tests**

All E2E tests need to:
1. Create a family before creating galleries
2. Navigate through the family flow first (click on family card → then galleries)
3. Update any direct URL navigation to include family_id

**Step 2: Commit**

```bash
git add test/web/e2e/ test/support/e2e_case.ex
git commit -m "Update E2E tests for family-scoped navigation"
```

---

### Task 16: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the Architecture section**

Update module naming from `Family` to `Ancestry`, add `families/` directory and context to the tree, update the photo processing flow to mention family scoping, add the Family feature documentation:

Key updates:
- Module namespace: `Ancestry.*` (was `Family.*`)
- OTP app: `:ancestry` (was `:family`)
- New context: `Ancestry.Families` — primary public API for families
- New schema: `Ancestry.Families.Family`
- New uploader: `Ancestry.Uploaders.FamilyCover`
- New worker: `Ancestry.Workers.ProcessFamilyCoverJob`
- URL structure: nested under `/families/:family_id/...`
- Photo storage: includes `family_id` in path
- Add Family entity to the architecture tree
- Update all `Family.*` references to `Ancestry.*`

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md with Ancestry rename and Family feature docs"
```

---

### Task 17: Run Full Test Suite and Precommit

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compiles without warnings, formats cleanly, all tests pass

**Step 2: Fix any issues found**

Address any compilation warnings, formatting issues, or test failures.

**Step 3: Final commit if fixes needed**

```bash
git add -A
git commit -m "Fix issues found during precommit"
```
