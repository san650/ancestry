# Memory Vaults — Design Spec

**Date:** 2026-04-09
**Status:** Draft
**Feature:** Rich-text memory journals organized into vaults within a family

## Overview

Memory Vaults let family members capture and share written memories — rich text notes that can embed photos from the family's albums and @mention people in the organization. Vaults are scoped to a family. Any authenticated member of the organization can view and contribute to vaults within families they have access to.

## Data Model

### memory_vaults

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| name | string | required |
| family_id | FK → families | on_delete: delete_all, indexed |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

### memories

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| name | string | required |
| content | text | Trix HTML (sanitized before rendering) |
| description | string | auto-generated: strip HTML + image refs to plain text, then take first 100 chars |
| cover_photo_id | FK → photos | nullable, on_delete: nilify |
| memory_vault_id | FK → memory_vaults | on_delete: delete_all, indexed |
| inserted_by | FK → accounts | on_delete: nilify, tracks creator |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

### memory_mentions (join table)

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| memory_id | FK → memories | on_delete: delete_all |
| person_id | FK → persons | on_delete: delete_all |
| | | unique index on [memory_id, person_id] |

### FK naming convention

Foreign keys that represent a role use descriptive names (`inserted_by`) rather than generic entity names (`account_id`). See learning `use-descriptive-fk-names`.

### Removed: memory_photos join table

Photo references embedded in Trix content are not tracked in a separate join table. The photo IDs exist structurally inside the HTML as `data-photo-id` attributes and are resolved at render time. If a need to query "all memories referencing a given photo" arises, this table can be added later.

## Context: Ancestry.Memories

### Schemas

- `Ancestry.Memories.Vault` → `memory_vaults`
- `Ancestry.Memories.Memory` → `memories`
- `Ancestry.Memories.MemoryMention` → `memory_mentions`

### Public API

```elixir
# Vaults
list_vaults(family_id)                # ordered by inserted_at desc
get_vault!(id)                        # preloads memory count
create_vault(family, attrs)
update_vault(vault, attrs)
delete_vault(vault)                   # cascade deletes all memories

# Memories
list_memories(vault_id)               # ordered by inserted_at desc, preloads cover_photo, account
get_memory!(id)                       # preloads mentions (with person), cover_photo, account
create_memory(vault, account, attrs)
update_memory(memory, attrs)
delete_memory(memory)
```

### Create/update memory transaction (Ecto.Multi)

1. Validate and insert/update the memory record
2. Auto-generate `description` — strip HTML tags and image references from `content` to plain text, then take first 100 chars
3. Sync `memory_mentions` — parse content HTML, extract person IDs, **validate they belong to the current organization**, delete all existing + re-insert

### PubSub

- Topic: `"vault:{vault_id}"`
- Events: `:memory_created`, `:memory_updated`, `:memory_deleted`
- Used by `VaultLive.Show` for real-time card updates

### ContentParser (private module)

`Ancestry.Memories.ContentParser` — takes Trix HTML, returns `{description, person_ids, photo_ids}`.

Uses `LazyHTML` (the Rust NIF HTML parser already in the project, not Floki) to walk the DOM tree and extract `data-person-id` and `data-photo-id` attributes from Trix attachment `<figure>` elements. Strips all HTML tags and image references to produce the plain-text description.

## Security

### HTML sanitization

Trix HTML stored in the `content` column is user-submitted. Although Trix produces clean markup during normal editing, users can bypass the editor by modifying the hidden `<input>` value or crafting WebSocket messages directly. **The HTML must be sanitized server-side before rendering.**

Use `HtmlSanitizeEx` (or a `LazyHTML`-based allowlist) to strip disallowed tags and attributes. Allowlist:

- **Tags:** `div`, `p`, `br`, `strong`, `em`, `del`, `blockquote`, `ul`, `ol`, `li`, `h1`, `a`, `pre`, `figure`, `figcaption`, `img`, `span`
- **Attributes:** `href` (restricted to `http`/`https`), `data-person-id`, `data-photo-id`, `data-trix-attachment`, `src`, `class`
- **Strip:** all event handlers (`onclick`, `onerror`, etc.), `javascript:` URIs, `<script>`, `<iframe>`, `<object>`, `<embed>`, `<style>`, `<link>`

Sanitization happens in `ContentRenderer` before output, not on storage (preserves the original for re-editing).

### Authorization

**Cross-tenant scoping:** Every new LiveView `mount` must:
1. Load the family by `family_id` from params
2. Verify `family.organization_id == current_scope.organization.id`
3. Verify the vault belongs to that family (`vault.family_id == family.id`)
4. For `MemoryLive.Form`, verify `memory.memory_vault_id == vault.id`

This matches the existing pattern in `GalleryLive.Show`.

**Memory CRUD:** Fully collaborative (wiki-style) — any org member can edit or delete any memory. The `inserted_by` field tracks the original author for attribution only.

### Photo picker validation

When a user selects a cover photo or inserts a photo into content:
- Album listing uses the validated `family_id` from socket assigns
- On photo selection, the server validates the photo belongs to a gallery owned by the current family before accepting it

### Person mention validation

Person IDs extracted from content by `ContentParser` are validated against the current organization before inserting `memory_mentions` records. Invalid IDs are silently dropped.

## Routes

All routes live inside the existing `live_session :organization` block scoped under `/org/:org_id/`.

```
/org/:org_id/families/:family_id/vaults/:vault_id                       → VaultLive.Show
/org/:org_id/families/:family_id/vaults/:vault_id/memories/new          → MemoryLive.Form, :new
/org/:org_id/families/:family_id/vaults/:vault_id/memories/:memory_id   → MemoryLive.Form, :edit
```

Vault creation uses a modal on `FamilyLive.Show` (same pattern as gallery creation). No separate route.

## LiveViews

### FamilyLive.Show (modified)

- Add a "Memory Vaults" section **above** the galleries section
- Vault cards in a responsive grid: single column on mobile, 2-3 columns on desktop
- Each card shows: vault name (bold), memory count, date of most recently inserted memory
- Click card → navigates to `VaultLive.Show`
- "New Vault" button opens a modal with a name field (same pattern as `show_new_gallery_modal` / `save_gallery`)
- Empty state: "No memory vaults yet" with create button

### VaultLive.Show (new)

- Header with vault name + "Add Memory" button
- Back navigation to family show page (back arrow on mobile, breadcrumb on desktop)
- Memory cards in a responsive grid: single column on mobile, 2-3 columns on desktop, newest first
- Delete vault option with confirmation modal → redirects to family show

**Memory card content:**
- Cover photo at top (landscape crop) — omitted entirely if no cover photo is set (no placeholder). Card is simply shorter without the image section.
- Memory name (bold)
- Description (auto-generated 100-char excerpt)
- Date (formatted inserted_at)
- Click card → navigates to `MemoryLive.Form` (:edit)

Note: `inserted_by` is stored in the DB for future use but not displayed in the UI for now.

**Real-time:** Subscribes to `"vault:{vault_id}"` PubSub topic. Stream operations for card updates.

### MemoryLive.Form (new — single LiveView with :new / :edit live actions)

- Name field (text input, required)
- Cover photo picker — button opens two-step album → photo modal. Shows selected thumbnail with "Remove" option. If none selected, just the button.
- Trix editor for content — with @mention support and "Insert Photo" toolbar button
- Save / Cancel buttons
- In `:edit` mode: also shows "Delete" option with confirmation modal
- On save → redirects to `VaultLive.Show`
- On delete → redirects to `VaultLive.Show`

### Album photo picker (reusable LiveComponent)

`Web.Live.Shared.AlbumPhotoPickerComponent` — used by both the cover photo picker and the "Insert Photo" toolbar action.

1. Modal opens showing all albums in the current family (scoped via `family_id` from socket assigns)
2. User selects an album → modal shows photo grid from that album
3. User selects a photo → modal closes, sends selected photo data back to parent
4. On mobile, modal goes full-screen; on desktop, centered dialog

### Responsive behavior (all new pages)

**Mobile (default):**
- Single column, full width
- Cover photos span full card width
- "Add Memory" button prominent at top
- Album/photo picker modal goes full-screen (per DESIGN.md)
- Trix editor full width with reasonable min-height

**Desktop (enhancement):**
- Card grids expand to 2-3 columns
- Max-width container for editor pages
- Picker modals are centered dialogs

## Trix Editor Integration

### JS dependencies (npm)

- `trix` v2 — the editor (~54 KB gzipped total, includes DOMPurify)

### Mentions: custom implementation (no @thoughtbot/trix-mentions-element)

`@thoughtbot/trix-mentions-element` hard-depends on Trix v1 and is incompatible with Trix v2. Mentions are implemented with a custom JS hook instead:

- The `TrixEditor` hook listens for text input and detects `@` followed by characters
- On `@` trigger, `pushEvent` sends the query to LiveView
- LiveView queries matching people in the organization and pushes results back via `push_event`
- The hook renders a dropdown overlay positioned near the cursor
- On selection, the hook calls `editor.insertAttachment()` to insert a content attachment with `data-person-id` and the display name
- Escape or clicking outside dismisses the dropdown

### File uploads disabled

`trix-file-accept` event is intercepted with `preventDefault()` to block drag-and-drop and paste uploads. Photos are only inserted via the album picker.

### JS Hook: TrixEditor

Single hook handling all Trix interactions:
- Mounts Trix inside a `phx-update="ignore"` wrapper
- Blocks file uploads via `trix-file-accept`
- Syncs content to hidden `<input>` on `trix-change`
- Handles `@` mention detection, dropdown rendering, and attachment insertion
- Handles "Insert Photo" custom toolbar button → pushes event to LiveView to open album picker
- Receives selected photo data back via `handleEvent` → calls `editor.insertAttachment()` to insert content attachment

### Trix HTML output

Mentions:
```html
<figure data-trix-attachment='{"contentType":"application/vnd.memory-mention",...}'>
  <span data-person-id="42">@John Smith</span>
</figure>
```

Photos:
```html
<figure data-trix-attachment='{"contentType":"application/vnd.memory-photo",...}'>
  <img data-photo-id="7" src="/uploads/photos/thumb_abc.jpg" />
</figure>
```

### npm/esbuild setup

- Add `trix` to `assets/package.json` as a production dependency
- Import Trix JS in the hook file (or dynamically in `mounted()` for code splitting)
- Import Trix CSS in `app.css` (Trix ships its own stylesheet; without it the editor renders unstyled)
- Per CLAUDE.md: vendor deps must be imported into app.js/app.css, no external script/link tags

## Rendering Memories

### ContentRenderer (private module)

`Ancestry.Memories.ContentRenderer` — takes sanitized Trix HTML and preloaded person data, returns safe HTML for rendering.

**Input:** The stored `content` HTML + a map of `%{person_id => %Person{}}` from preloaded `memory_mentions`.

**Processing:**
1. **Sanitize** — run through HTML allowlist (see Security section)
2. **Mentions:** `<figure>` with `data-person-id` → `<a href="/org/:org_id/people/:id">@Name</a>` wrapped with a positioned container holding a hidden hover card
3. **Photos:** `<figure>` with `data-photo-id` → `<img>` with current Waffle URLs
4. **All other HTML:** Passed through (already sanitized)

Uses `LazyHTML` for parsing and transformation.

### Person hover card (@mentions)

**CSS-only approach, desktop enhancement only:**

- Each rendered mention link is wrapped with a positioned container holding a hidden card
- On `:hover` (desktop only) the card is shown via CSS
- On mobile, no hover card appears — tapping the mention link navigates directly to the person show page
- This aligns with DESIGN.md: "Hover may enhance the UI, but must never be required"

**Card content:**
- Person photo thumbnail (or initials placeholder if no photo)
- Full name
- Birth/death years (if available)
- Click navigates to person show page (`/org/:org_id/people/:id`)

## Testing

### Context tests
- `Ancestry.MemoriesTest` — CRUD for vaults and memories, Ecto.Multi transaction, mention sync, description auto-generation, cascade deletes

### ContentParser tests
- Extract person IDs and photo IDs from Trix HTML
- Generate description from content (strips HTML, strips image refs, truncates to 100 chars)
- Handle edge cases: empty content, no mentions, no photos, malformed HTML

### ContentRenderer tests
- Sanitization: strips disallowed tags/attributes, preserves allowed ones
- Mention rendering: generates correct links and hover card markup
- Photo rendering: generates correct img tags with Waffle URLs
- Edge cases: missing person data, deleted photos

### User flow tests (test/user_flows/)
- Create a vault from family show page (modal)
- Navigate to vault, create a memory with name and content
- Edit a memory
- Delete a memory
- Delete a vault (cascade)

### LiveView-specific
- Trix content syncs to form on submit
- Album photo picker modal opens and inserts photo
- @mention search returns matching people
- Real-time updates via PubSub (another user adds a memory)
- Authorization: cannot access vaults from another organization
