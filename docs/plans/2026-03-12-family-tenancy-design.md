# Family Tenancy Design

## Overview

Add a top-level `Family` entity that acts as a tenant for the application. Galleries (and future entities) belong to a Family. Users must pick a Family before navigating to galleries.

Also rename the base module from `Family` to `Ancestry` and OTP app from `:family` to `:ancestry` to avoid naming collisions.

## Data Model

### Family schema (`Ancestry.Families.Family`)

- `name` — string, required, validated 1-255 chars
- `cover` — string (Waffle.Ecto attachment metadata)
- `cover_status` — string, default `nil`. Set to `"pending"` when cover uploaded, then `"processed"` or `"failed"` after Oban job runs
- `timestamps()`

### Gallery schema changes

- Add `family_id` — references families, on_delete: cascade
- Add `belongs_to :family, Ancestry.Families.Family`

### Seed

Insert "My Family" in `seeds.exs`.

## Module Rename

- **OTP app:** `:family` → `:ancestry`
- **Modules:** `Family.*` → `Ancestry.*`
- **Config:** all references to `:family` → `:ancestry`
- **Database names:** `family_dev`/`family_test` → `ancestry_dev`/`ancestry_test`
- **Web layer stays `Web`** (already decoupled)

## File Storage

### Cover photo

- Waffle uploader: `Ancestry.Uploaders.FamilyCover`
- Single version: `:cover` (1200x800 max, maintain aspect ratio)
- Accepts: `.jpg`, `.jpeg`, `.png`, `.webp`
- Path: `priv/static/uploads/families/{family_id}/cover.{ext}`

### Gallery photo path update

- From: `priv/static/uploads/photos/{gallery_id}/{photo_id}/`
- To: `priv/static/uploads/photos/{family_id}/{gallery_id}/{photo_id}/`
- Original temp files stay at: `priv/static/uploads/originals/{uuid}/`

### Oban worker (`Ancestry.Workers.ProcessFamilyCoverJob`)

- Queue: `:photos` (reuse existing)
- Same pattern as `ProcessPhotoJob`
- Broadcasts `{:cover_processed, family}` or `{:cover_failed, family}` on PubSub topic `"family:{id}"`

## Routes

```
/                                          → FamilyLive.Index (landing page, family grid)
/families/new                              → FamilyLive.New (create family)
/families/:family_id                       → FamilyLive.Show (edit/delete family)
/families/:family_id/galleries             → GalleryLive.Index (galleries within family)
/families/:family_id/galleries/:id         → GalleryLive.Show (photos within gallery)
```

## Context API

### `Ancestry.Families`

- `list_families/0` — all families ordered by name
- `get_family!/1` — fetch by id
- `create_family/1` — create with name
- `update_family/2` — update name and/or cover
- `delete_family!/1` — delete family, cascade, clean up files on disk
- `change_family/2` — changeset for forms

### `Ancestry.Galleries` changes

- `list_galleries/1` — takes `family_id`, scopes query
- `create_gallery/1` — attrs must include `family_id`

## UI Design

### Family Index (landing page `/`)

- Grid of family cards (responsive)
- Each card: cover photo (or fallback placeholder), family name
- "New Family" button in toolbar
- Click card → `/families/:family_id/galleries`
- Hover reveals edit/delete actions

### New Family

- Form with name (required) and cover photo upload (optional)
- Cover photo preview before submit
- On submit: create family, enqueue cover job if photo, redirect to gallery index

### Edit Family

- Edit name and replace cover photo
- Cover shows pending state while processing

### Delete Family

- Confirmation modal with family name
- Deletes family, all galleries, photos, and files on disk

### Family Gallery Index (`/families/:family_id/galleries`)

- Same as current gallery index, scoped to family
- Toolbar shows family name + back button to `/`

## File Cleanup on Family Delete

- Delete `priv/static/uploads/families/{family_id}/`
- Delete `priv/static/uploads/photos/{family_id}/`

## PubSub Topics

- `"family:{id}"` — cover processing updates
- `"gallery:{id}"` — photo processing updates (unchanged)
