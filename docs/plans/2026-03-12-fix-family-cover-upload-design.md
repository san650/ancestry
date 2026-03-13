# Fix Family Cover Upload & Index Display

## Problem

Two issues with family cover photos:

1. **Bug:** Cover photo is uploaded and processed by Waffle/ImageMagick, but the `cover` field in the database is never populated. `update_cover_processed/1` only sets `cover_status` to `"processed"` without writing the URL.
2. **Missing feature:** The families index page always shows a placeholder icon — it never renders the cover image.

## Design

### Bug fix

**Root cause:** `ProcessFamilyCoverJob.process_cover/2` calls `Families.update_cover_processed(family)` after Waffle stores the file, but that function never writes the cover URL to the DB.

**Fix:**
- After `Uploaders.FamilyCover.store/1` succeeds, generate the URL via `Uploaders.FamilyCover.url({"cover.jpg", family}, :cover)`
- Update `Families.update_cover_processed/2` to accept the URL and write both `cover: url` and `cover_status: "processed"`
- Update `ProcessFamilyCoverJob.process_cover/2` to pass the URL through

**Files:** `lib/ancestry/families.ex`, `lib/ancestry/workers/process_family_cover_job.ex`

### Index page cover display

Replace the static `hero-users` icon in each family card with a conditional:
- If `family.cover` exists: render `<img>` as card header (`h-32`, `object-cover`, rounded top)
- If no cover: fall back to the existing icon placeholder

**Files:** `lib/web/live/family_live/index.html.heex`

### E2E test

Full async flow test in `test/web/e2e/family_cover_test.exs`:
1. Visit `/families/new`, fill in name, upload cover image
2. Submit form (family created, navigated to galleries page)
3. Navigate to index page (`/`)
4. Assert cover image appears on the family card (with timeout for Oban processing)

Uses existing `Web.E2ECase` and `upload_image/3` helper.

## Scope

- No schema migration needed — `cover` field already exists
- No new dependencies
- Three files changed, one test file added
