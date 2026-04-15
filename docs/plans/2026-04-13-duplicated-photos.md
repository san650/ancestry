# Duplicated Photos Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent duplicate photo uploads within a gallery by hashing file contents and silently skipping already-present files.

**Architecture:** Add a `file_hash` column (SHA-256, hex) to `photos`. Before storing an upload, compute the hash and check for an existing match in the same gallery. Duplicates are reported as successful uploads. No schema or architectural changes beyond the new column and a `store_original_bytes/2` variant in `Storage`.

**Tech Stack:** Ecto migration, `:crypto` (SHA-256), Elixir, Phoenix LiveView

**Spec:** `docs/plans/2026-04-13-duplicated-photos-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `priv/repo/migrations/*_add_file_hash_to_photos.exs` | Add `file_hash` column + partial unique index |
| Modify | `lib/ancestry/galleries/photo.ex` | Add `file_hash` field, cast in changeset |
| Modify | `lib/ancestry/galleries.ex` | Add `photo_exists_in_gallery?/2`, pass `file_hash` through `create_photo/1` |
| Modify | `lib/ancestry/storage.ex` | Add `store_original_bytes/2` |
| Modify | `lib/web/live/gallery_live/show.ex` | Hash computation + duplicate check in `process_uploads/1` |
| Modify | `test/ancestry/galleries_test.exs` | Tests for `photo_exists_in_gallery?/2` and `file_hash` in `create_photo` |
| Modify | `test/support/factory.ex` | Add `file_hash` to `photo_factory` |

---

## Task 1: Migration — add `file_hash` column

**Files:**
- Create: `priv/repo/migrations/*_add_file_hash_to_photos.exs`

- [ ] **Step 1: Generate migration**

Run: `cd /Users/babbage/Work/ancestry && mix ecto.gen.migration add_file_hash_to_photos`

- [ ] **Step 2: Write migration**

```elixir
defmodule Ancestry.Repo.Migrations.AddFileHashToPhotos do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :file_hash, :string
    end

    create unique_index(:photos, [:gallery_id, :file_hash],
      where: "file_hash IS NOT NULL",
      name: :photos_gallery_id_file_hash_index
    )
  end
end
```

- [ ] **Step 3: Run migration**

Run: `cd /Users/babbage/Work/ancestry && mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 4: Commit**

```
feat: add file_hash column to photos table
```

---

## Task 2: Schema + Context — `file_hash` field and duplicate check

**Files:**
- Modify: `lib/ancestry/galleries/photo.ex:6-24`
- Modify: `lib/ancestry/galleries.ex:39-44`
- Test: `test/ancestry/galleries_test.exs`
- Modify: `test/support/factory.ex:32-40`

- [ ] **Step 1: Write failing test for `photo_exists_in_gallery?/2`**

Add to `test/ancestry/galleries_test.exs` inside the `describe "photos"` block:

```elixir
test "photo_exists_in_gallery?/2 returns true when hash exists in gallery", %{gallery: gallery} do
  {:ok, _photo} =
    Galleries.create_photo(%{
      gallery_id: gallery.id,
      original_path: "/tmp/test.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg",
      file_hash: "abc123"
    })

  assert Galleries.photo_exists_in_gallery?(gallery.id, "abc123")
end

test "photo_exists_in_gallery?/2 returns false when hash does not exist", %{gallery: gallery} do
  refute Galleries.photo_exists_in_gallery?(gallery.id, "nonexistent")
end

test "photo_exists_in_gallery?/2 returns false when same hash is in different gallery", %{
  gallery: gallery,
  family: family
} do
  {:ok, other_gallery} = Galleries.create_gallery(%{name: "Other", family_id: family.id})

  {:ok, _photo} =
    Galleries.create_photo(%{
      gallery_id: other_gallery.id,
      original_path: "/tmp/test.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg",
      file_hash: "abc123"
    })

  refute Galleries.photo_exists_in_gallery?(gallery.id, "abc123")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/babbage/Work/ancestry && mix test test/ancestry/galleries_test.exs --trace`
Expected: 3 failures — `photo_exists_in_gallery?/2` is undefined, `file_hash` not cast.

- [ ] **Step 3: Add `file_hash` to Photo schema and changeset**

In `lib/ancestry/galleries/photo.ex`:

Add `field :file_hash, :string` to the schema block (after `field :status`).

Update `changeset/2` to cast `:file_hash`:

```elixir
def changeset(photo, attrs) do
  photo
  |> cast(attrs, [:gallery_id, :original_path, :original_filename, :content_type, :status, :file_hash])
  |> validate_required([:gallery_id, :original_path, :original_filename, :content_type])
  |> foreign_key_constraint(:gallery_id)
end
```

- [ ] **Step 4: Add `photo_exists_in_gallery?/2` to Galleries context**

In `lib/ancestry/galleries.ex`, add:

```elixir
def photo_exists_in_gallery?(gallery_id, file_hash) do
  Repo.exists?(
    from p in Photo,
      where: p.gallery_id == ^gallery_id and p.file_hash == ^file_hash
  )
end
```

- [ ] **Step 5: Update photo factory**

In `test/support/factory.ex`, add `file_hash: nil` to `photo_factory`:

```elixir
def photo_factory do
  %Ancestry.Galleries.Photo{
    gallery: build(:gallery),
    original_path: "test/fixtures/test_image.jpg",
    original_filename: "test.jpg",
    content_type: "image/jpeg",
    status: "processed",
    file_hash: nil
  }
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/babbage/Work/ancestry && mix test test/ancestry/galleries_test.exs --trace`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```
feat: add file_hash field to Photo schema and photo_exists_in_gallery?/2
```

---

## Task 3: Storage — add `store_original_bytes/2`

**Files:**
- Modify: `lib/ancestry/storage.ex:9-25`

- [ ] **Step 1: Add `store_original_bytes/2` to Storage**

In `lib/ancestry/storage.ex`, add a new function that accepts already-read bytes instead of a file path:

```elixir
def store_original_bytes(contents, dest_key) do
  case storage_backend() do
    Waffle.Storage.S3 ->
      ExAws.S3.put_object(bucket(), dest_key, contents)
      |> ExAws.request!()

      dest_key

    _ ->
      dest_path = Path.join(local_prefix(), dest_key)
      dest_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(dest_path, contents)
      dest_path
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/babbage/Work/ancestry && mix compile --warnings-as-errors`
Expected: Compiles without warnings.

- [ ] **Step 3: Commit**

```
feat: add Storage.store_original_bytes/2 for pre-read file contents
```

---

## Task 4: Upload flow — duplicate detection in `process_uploads/1`

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex:220-263`

- [ ] **Step 1: Update `process_uploads/1` to hash and check for duplicates**

Replace the `process_uploads/1` function in `lib/web/live/gallery_live/show.ex`:

```elixir
defp process_uploads(socket) do
  gallery = socket.assigns.gallery

  results =
    consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
      contents = File.read!(tmp_path)

      file_hash =
        :crypto.hash(:sha256, contents)
        |> Base.encode16(case: :lower)

      if Galleries.photo_exists_in_gallery?(gallery.id, file_hash) do
        {:ok, {:duplicate, entry.client_name}}
      else
        uuid = Ecto.UUID.generate()
        ext = ext_from_content_type(entry.client_type)
        dest_key = Path.join(["uploads", "originals", uuid, "photo#{ext}"])
        original_path = Ancestry.Storage.store_original_bytes(contents, dest_key)

        case Galleries.create_photo(%{
               gallery_id: gallery.id,
               original_path: original_path,
               original_filename: entry.client_name,
               content_type: entry.client_type,
               file_hash: file_hash
             }) do
          {:ok, photo} -> {:ok, {:ok, photo}}
          {:error, _} -> {:ok, {:error, entry.client_name}}
        end
      end
    end)

  {uploaded, errored} =
    Enum.split_with(results, fn
      {:ok, _} -> true
      {:duplicate, _} -> true
      {:error, _} -> false
    end)

  uploaded_photos =
    Enum.flat_map(uploaded, fn
      {:ok, photo} -> [photo]
      {:duplicate, _} -> []
    end)

  upload_results =
    Enum.map(uploaded, fn
      {:ok, photo} -> %{name: photo.original_filename, status: :ok}
      {:duplicate, name} -> %{name: name, status: :ok}
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

Key changes from the original:
- Read file bytes before storing (`File.read!(tmp_path)`)
- Compute SHA-256 hash
- Check `photo_exists_in_gallery?/2` — if duplicate, return `{:duplicate, name}` without storing
- Use `store_original_bytes/2` instead of `store_original/2` (avoids double read)
- Pass `file_hash` to `create_photo`
- Duplicates are reported with `status: :ok` in `upload_results` (indistinguishable from new uploads)

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/babbage/Work/ancestry && mix compile --warnings-as-errors`
Expected: Compiles without warnings.

- [ ] **Step 3: Commit**

```
feat: detect and skip duplicate photo uploads in gallery
```

---

## Task 5: Run full test suite

- [ ] **Step 1: Run precommit**

Run: `cd /Users/babbage/Work/ancestry && mix precommit`
Expected: All checks pass — compilation, formatting, tests.

- [ ] **Step 2: Fix any failures**

If any test fails, fix and re-run.

- [ ] **Step 3: Final commit if any fixes were needed**

```
fix: address test/lint issues from duplicate photo detection
```
