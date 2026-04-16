# Photo Comments: Account Linking & Avatars

## Summary

Link accounts to photo comments so each message shows who wrote it. Display round avatars (account photo if available, initials with hash-based color as fallback) and author names. Make the comment layout more compact with a responsive design: bubble-style on desktop, ultra-compact inline on mobile. Enforce owner-based edit/delete permissions.

## Data Model

### Migration: Add `account_id` to `photo_comments`

- Add `account_id` column referencing `accounts` with `on_delete: :nilify_all`
- Nullable — existing comments keep `account_id: nil`
- Add index on `account_id`

### Schema: `PhotoComment`

- Add `belongs_to :account, Ancestry.Identity.Account`
- Changeset unchanged — `account_id` is set server-side, not cast from params

### `Account` schema

Already has `name`, `avatar`, `avatar_status` fields. No new fields needed. Optionally add `has_many :photo_comments, Ancestry.Comments.PhotoComment` for the inverse association.

## Avatar System

### Module: `Ancestry.Avatars`

Pure functions, no DB access.

- `initials(account)` — accepts an `Account` struct (or nil). Uses `name` if present, falls back to first letter of email prefix, or `"?"` if nothing available. Extracts first letter of first and last word, uppercased. Single-word names → one letter.
- `color(account_id)` — deterministic color from a curated palette of 10–12 distinguishable colors, selected by `rem(account_id, length(palette))`

### Avatar rendering priority

1. Account has `avatar` field set and `avatar_status == "processed"` → render round `<img>` with the uploaded photo
2. Otherwise → render round `<div>` with initials and hash-based background color

### Shared function component

Defined in `lib/web/components/avatar_components.ex`. Accepts `account` assign and `size` attribute (`:sm` = 22px, `:md` = 28px). Imported in `lib/web.ex` so it's available in all LiveViews and components. Used in both comment list and new comment input.

## Context & Query Changes

### `Ancestry.Comments`

- `create_photo_comment/3` — new signature: `create_photo_comment(photo_id, account_id, attrs)`. Both `photo_id` and `account_id` set via `put_change` server-side, not cast from form params. Only `text` comes from `attrs`.
- `list_photo_comments/1` — preload `:account` association so name/avatar are available without N+1.
- All PubSub broadcasts (`{:comment_created, comment}`, `{:comment_updated, comment}`, `{:comment_deleted, comment}`) preload `:account` on the comment before broadcasting, so stream inserts/updates render avatars correctly without re-query.

## UI: Responsive Comment Layout

### Desktop (md+ breakpoint) — Bubble style

- 28px round avatar (photo or initials fallback)
- Author name above the message (11px, muted color)
- Message text in a subtle `bg-white/8` rounded bubble
- Timestamp below the bubble (10px)
- Edit/delete buttons appear on hover within the comment row

### Mobile (default) — Ultra-compact inline

- 22px round avatar (photo or initials fallback)
- First name bold, inline with message text
- Short relative time at end of the text line
- No bubble background — plain text flow
- Edit/delete via hover/tap on the row

### New comment input

- Current user's avatar to the left of the textarea (22px mobile, 28px desktop)
- Same textarea + send button layout, avatar prepended

## Permissions (via Permit)

Authorization uses the project's Permit system, not inline role checks.

### `Ancestry.Permissions` rules

Add `PhotoComment` rules to `can/1`:

- All authenticated users can `:create` `PhotoComment`
- Owner (where `comment.account_id == scope.account.id`) can `:edit` and `:delete` their own `PhotoComment`
- Admin can `:delete` any `PhotoComment`

### Template visibility

Use `can?/3` helpers in templates:
- **Edit button**: `can?(current_scope, :edit, comment)`
- **Delete button**: `can?(current_scope, :delete, comment)`

### Server-side enforcement

`handle_event` for edit and delete uses `authorized?/3` or equivalent Permit check. Non-authorized attempts are no-ops.

### `PhotoCommentsComponent` changes

- Receives `current_scope` from the parent LiveView (passed as assign)
- `save_comment` uses `current_scope.account.id` to set the author

## Edge Cases

- **`account_id: nil` (pre-migration comments)**: render with `"?"` avatar and "Unknown" name. No edit button. Delete only for admins.
- **Deleted accounts (`on_delete: :nilify_all`)**: same treatment as nil — "Unknown" with fallback avatar.
- **Account with no `name` set**: `Avatars.initials/1` falls back to first letter of email prefix, or `"?"` if nothing available (handled by accepting the account struct, not just name string).

## Testing

### E2E tests (`test/user_flows/`)

- Comment displays author name and avatar
- Only comment owner sees edit button
- Only comment owner and admins see delete button
- Non-owner cannot edit another user's comment (server-side check)
- Admin can delete any comment
- Pre-existing comments (nil account) render with fallback avatar and "Unknown" name

### Unit tests

- `Ancestry.Avatars.initials/1` — account with full name, single-word name, no name (email fallback), nil account
- `Ancestry.Avatars.color/1` — returns consistent color for same ID, stays within palette bounds
