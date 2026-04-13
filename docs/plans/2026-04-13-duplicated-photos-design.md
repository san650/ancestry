# Duplicated Photos Detection — Design Spec

**Date:** 2026-04-13
**Status:** Approved

## Problem

Users can upload the same photo multiple times to a gallery, resulting in duplicate entries. There is no mechanism to detect or prevent this.

## Solution

Add a `file_hash` column to the `photos` table containing the SHA-256 hash of the original file bytes. Before storing a new upload, check if a photo with the same hash already exists in the target gallery. If it does, skip storage and record creation but report the upload as successful — the user's intent (photo in the gallery) is already fulfilled.

## Approach

**Server-side hash with per-gallery uniqueness (Approach A)**

- Compute SHA-256 hash during upload, before storing the original
- Duplicate check is scoped to the current gallery only
- Same photo uploaded to different galleries creates separate records and separate S3 files (leaves the door open for future cross-gallery file sharing)
- Hash stored as lowercase hex string (64 chars)

### Alternatives considered

- **Client-side pre-flight hash (B):** Saves bandwidth for large duplicates but adds JS hook complexity. Can be layered on later.
- **Filename + size heuristic (C):** Unreliable — different photos can share name/size, renamed identical photos slip through.

## Data layer

### Migration

- Add `file_hash` column to `photos` table — `string`, nullable (existing photos won't have a hash)
- Add partial unique index on `(gallery_id, file_hash)` where `file_hash IS NOT NULL`

### Schema

- `Photo` gets `field :file_hash, :string`
- `Photo.changeset/2` casts `file_hash`

### Context

- Add `Galleries.photo_exists_in_gallery?(gallery_id, file_hash)` — returns boolean

## Upload flow changes

In `GalleryLive.Show.process_uploads/1`, for each uploaded entry:

1. Read temp file bytes
2. Compute `file_hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)`
3. Check `Galleries.photo_exists_in_gallery?(gallery.id, file_hash)`
   - **Duplicate:** Don't store original, don't create record, don't enqueue Oban job. Return the existing photo as a success result.
   - **New:** Proceed as today — store original, create photo with `file_hash` in attrs, enqueue processing job.

### Storage refactor

`Storage.store_original/2` currently reads the file bytes itself (`File.read!(tmp_path)`). Since we need the bytes before calling storage (to compute the hash and check for duplicates), add `Storage.store_original_bytes/2` that accepts already-read bytes and a destination key, avoiding a double read.

## UX

- Duplicate uploads appear in the upload results modal as successful (green checkmark, same as new uploads)
- No error, no warning — the photo is already in the gallery, user intent is fulfilled
- No visible distinction between "newly uploaded" and "already existed"

## Testing

- **E2E:** Upload same file twice to same gallery — second upload shows success, only one photo record exists in DB
- **E2E:** Upload same file to different galleries — both succeed, two separate records exist
- **Unit:** `Galleries.photo_exists_in_gallery?/2` returns true/false correctly
