# Fix 404 Errors in E2E Tests

## Bug

Running `mix test` prints `[error] Failed to load resource: the server responded with a status of 404` for three types of uploads:
- `/uploads/people/{id}/thumbnail.jpg` — person photos (from Oban inline processing)
- `/uploads/families/{id}/cover.jpg` — family covers (from Oban inline processing)
- `/uploads/photos/{family_id}/{gallery_id}/{photo_id}/thumbnail.jpg.jpg` — gallery photos (from factory)

## Root Cause

Two separate causes:

1. **Oban inline processing writes to wrong directory.** In test, Waffle is configured with `storage_dir_prefix: "tmp/test_uploads"`, but the endpoint's `Plug.Static` serves from `priv/static/`. When Oban processes uploads inline during E2E tests, files land in `tmp/test_uploads/uploads/...` but the browser requests them from `/uploads/...` which maps to `priv/static/uploads/...`.

2. **Factory creates "processed" records with no files.** `insert(:photo)` sets `status: "processed"` by default, causing templates to render `<img>` tags pointing to files that were never created. Person and family factories don't set photo/cover fields, so they are only affected by cause 1 (Oban processing), not cause 2.

## Fix

### 1. Test-only `Plug.Static` in endpoint

Add a second `Plug.Static` in `endpoint.ex` that serves from `tmp/test_uploads` only in test:

```elixir
if Mix.env() == :test do
  plug Plug.Static,
    at: "/",
    from: "tmp/test_uploads",
    only: ~w(uploads)
end
```

Place before the existing `Plug.Static`. This fixes Oban-processed files (person photos, family covers).

### 2. Placeholder file helper in E2ECase

Add `ensure_photo_file/1` helper to `test/support/e2e_case.ex` that creates placeholder image files at the paths Waffle expects.

Note: Waffle's `Photo` uploader generates filenames like `thumbnail.jpg` and the transform outputs `:jpg`, causing Waffle to append a second `.jpg` extension. The actual file on disk must match: `thumbnail.jpg.jpg`, `large.jpg.jpg`.

```elixir
def ensure_photo_file(%Ancestry.Galleries.Photo{} = photo) do
  photo = Ancestry.Repo.preload(photo, :gallery)
  dir = Path.join(["tmp/test_uploads/uploads/photos",
    "#{photo.gallery.family_id}", "#{photo.gallery_id}", "#{photo.id}"])
  File.mkdir_p!(dir)
  source = "test/fixtures/test_image.jpg"
  # Waffle appends .jpg to the filename for transformed versions, producing double extensions
  File.cp!(source, Path.join(dir, "thumbnail.jpg.jpg"))
  File.cp!(source, Path.join(dir, "large.jpg.jpg"))
  File.cp!(source, Path.join(dir, "original#{Path.extname(photo.original_filename)}"))
  photo
end
```

Call in test setups that use `insert(:photo)`:

```elixir
insert(:photo, gallery: gallery) |> ensure_photo_file()
```

### 3. Clean up `tmp/test_uploads` between runs

No explicit cleanup needed — `tmp/test_uploads` paths use unique DB IDs so files don't collide between runs. `/tmp/` is already in `.gitignore`.

## Verification

Run `mix test 2>&1 | grep "\[error\]"` — should return zero lines.
All existing tests should continue to pass.
