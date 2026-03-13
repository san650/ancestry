# Fix Family Cover Upload & Index Display — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the bug where family cover photos are uploaded but never saved to the DB, add cover display to the index page, and write an E2E test for the full flow.

**Architecture:** Convert `Family.cover` to use `Waffle.Ecto` (matching the `Photo` schema pattern), fix `ProcessFamilyCoverJob` to store the filename after processing, update the index template to display covers. E2E test exercises the full async upload → Oban processing → display flow.

**Tech Stack:** Phoenix LiveView, Waffle + Waffle.Ecto, Oban, PhoenixTest.Playwright (E2E)

---

### Task 1: Fix Family schema to use Waffle.Ecto

**Files:**
- Modify: `lib/ancestry/families/family.ex`
- Modify: `lib/ancestry/uploaders/family_cover.ex`

**Step 1: Update FamilyCover uploader to support Waffle.Ecto Type**

The uploader already uses `Waffle.Definition`. Waffle.Ecto automatically provides a `.Type` module when `use Waffle.Definition` is present — no uploader changes needed.

**Step 2: Update Family schema to use Waffle.Ecto**

In `lib/ancestry/families/family.ex`:

```elixir
defmodule Ancestry.Families.Family do
  use Ecto.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "families" do
    field :name, :string
    field :cover, Ancestry.Uploaders.FamilyCover.Type
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

Changes: add `use Waffle.Ecto.Schema`, change `field :cover, :string` to `field :cover, Ancestry.Uploaders.FamilyCover.Type`.

**Step 3: Compile and verify no errors**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds.

---

### Task 2: Fix ProcessFamilyCoverJob to store cover filename

**Files:**
- Modify: `lib/ancestry/workers/process_family_cover_job.ex`
- Modify: `lib/ancestry/families.ex`

**Step 1: Update `Families.update_cover_processed/2` to accept and store the filename**

In `lib/ancestry/families.ex`, change `update_cover_processed/1` to `update_cover_processed/2`:

```elixir
def update_cover_processed(%Family{} = family, filename) do
  family
  |> Ecto.Changeset.change(%{
    cover: %{file_name: filename, updated_at: nil},
    cover_status: "processed"
  })
  |> Repo.update()
end
```

This follows the exact pattern from `Galleries.update_photo_processed/2`.

**Step 2: Update `ProcessFamilyCoverJob.process_cover/2` to pass the filename**

In `lib/ancestry/workers/process_family_cover_job.ex`, update the `process_cover/2` function:

```elixir
defp process_cover(family, original_path) do
  waffle_file = %{
    filename: Path.basename(original_path),
    path: original_path
  }

  case Uploaders.FamilyCover.store({waffle_file, family}) do
    {:ok, filename} -> Families.update_cover_processed(family, filename)
    {:error, reason} -> {:error, reason}
  end
end
```

Change: `{:ok, _filename}` → `{:ok, filename}` and pass it to `update_cover_processed/2`.

**Step 3: Compile and verify**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds.

---

### Task 3: Fix existing worker test

**Files:**
- Modify: `test/ancestry/workers/process_family_cover_job_test.exs`

**Step 1: Update test assertion to verify cover field is populated**

The existing test at `test/ancestry/workers/process_family_cover_job_test.exs:22` only checks `cover_status`. Add assertion that `cover` is also set:

```elixir
test "processes cover photo and updates family status", %{family: family, tmp_path: tmp_path} do
  assert :ok =
           perform_job(ProcessFamilyCoverJob, %{
             family_id: family.id,
             original_path: tmp_path
           })

  updated = Families.get_family!(family.id)
  assert updated.cover_status == "processed"
  assert updated.cover
end
```

**Step 2: Run the test to verify it passes**

Run: `mix test test/ancestry/workers/process_family_cover_job_test.exs`
Expected: Both tests pass.

**Step 3: Commit**

```
fix: store cover filename in DB after Waffle processing

ProcessFamilyCoverJob was discarding the filename returned by
Waffle.store/1, so the cover field was never populated. Now passes
the filename through update_cover_processed/2, matching the Photo
processing pattern. Family schema updated to use Waffle.Ecto.
```

---

### Task 4: Update FamilyLive.Show to use Waffle URL

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

**Step 1: Update show template to generate cover URL via Waffle**

In `lib/web/live/family_live/show.html.heex`, change the cover image display (line 35-36):

Old:
```heex
<%= if @family.cover do %>
  <img src={@family.cover} alt={@family.name} class="w-full h-full object-cover" />
```

New:
```heex
<%= if @family.cover do %>
  <img
    src={Ancestry.Uploaders.FamilyCover.url({@family.cover, @family}, :cover)}
    alt={@family.name}
    class="w-full h-full object-cover"
  />
```

**Step 2: Compile and verify**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds.

---

### Task 5: Add cover photo to FamilyLive.Index

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex`

**Step 1: Update family card to show cover image**

In `lib/web/live/family_live/index.html.heex`, replace the icon block (lines 33-35) with a conditional cover image as the card header:

Old:
```heex
<.link navigate={~p"/families/#{family.id}/galleries"} class="block p-6">
  <div class="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
    <.icon name="hero-users" class="w-6 h-6 text-primary" />
  </div>
  <h2 data-family-name class="text-lg font-semibold text-base-content truncate">
```

New:
```heex
<.link navigate={~p"/families/#{family.id}/galleries"} class="block">
  <%= if family.cover do %>
    <div class="h-32 overflow-hidden">
      <img
        src={Ancestry.Uploaders.FamilyCover.url({family.cover, family}, :cover)}
        alt={family.name}
        class="w-full h-full object-cover"
      />
    </div>
  <% else %>
    <div class="h-32 bg-base-200 flex items-center justify-center">
      <.icon name="hero-users" class="w-8 h-8 text-base-content/20" />
    </div>
  <% end %>
  <div class="p-4">
  <h2 data-family-name class="text-lg font-semibold text-base-content truncate">
```

Also close the `<div class="p-4">` wrapper after the date paragraph:

Old:
```heex
  <p class="text-sm text-base-content/50 mt-1">
    {Calendar.strftime(family.inserted_at, "%B %d, %Y")}
  </p>
</.link>
```

New:
```heex
  <p class="text-sm text-base-content/50 mt-1">
    {Calendar.strftime(family.inserted_at, "%B %d, %Y")}
  </p>
  </div>
</.link>
```

**Step 2: Compile and verify**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds.

**Step 3: Commit**

```
feat: display family cover photo on index and show pages

Index page now shows cover as card header image when available,
with a placeholder icon when not. Show page updated to generate
cover URL via Waffle uploader.
```

---

### Task 6: Write E2E test for full cover upload flow

**Files:**
- Create: `test/web/e2e/family_cover_test.exs`

**Step 1: Write the E2E test**

```elixir
defmodule Web.E2E.FamilyCoverTest do
  use Web.E2ECase

  @moduletag ecto_sandbox_stop_owner_delay: 200

  test "creating a family with a cover photo shows cover on index", %{conn: conn} do
    conn
    |> visit(~p"/families/new")
    |> wait_liveview()
    |> fill_in("Family name", with: "Cover Test Family")
    |> upload_image(
      "#new-family-form input[type=file]",
      [Path.absname("test/fixtures/test_image.jpg")]
    )
    |> click_button("Create")
    |> wait_liveview()
    # After creation, we land on the galleries page. Navigate to index.
    |> visit(~p"/")
    |> wait_liveview()
    |> assert_has("[data-family-name]", text: "Cover Test Family", timeout: 15_000)
    |> assert_has("#families img", timeout: 15_000)
  end
end
```

**Step 2: Run the test to verify it fails (before fix) or passes (after fix)**

Run: `mix test test/web/e2e/family_cover_test.exs`
Expected: PASS (since bug fix is already applied in earlier tasks).

**Step 3: Commit**

```
test: add E2E test for family cover upload and index display
```

---

### Task 7: Run precommit

**Step 1: Run precommit checks**

Run: `mix precommit`
Expected: All checks pass (compile, format, tests).

**Step 2: Fix any issues that arise and re-run until green.**
