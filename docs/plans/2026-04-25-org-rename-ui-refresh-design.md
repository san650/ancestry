# Design: Update Organization Name + UI Refresh

## Summary

Two related changes to the organization and family index pages:

1. **UI Refresh** — White page background with a new `shadow-ds-card` token for grounded card elevation. Applied to org index and family index as the new common pattern.
2. **Rename Organization** — Admins can rename an organization via the existing selection mode. Select one org, tap "Rename" in the selection bar, edit in a modal.

## Decisions

| Question | Decision |
|----------|----------|
| Page background | Pure white (`bg-white`) replaces `bg-ds-surface-low` |
| Card shadow | New `shadow-ds-card` token: `0 1px 3px rgba(11,28,48,0.08), 0 4px 12px rgba(11,28,48,0.04)` |
| Existing `shadow-ds-ambient` | Reserved for floating layers (modals, popovers) |
| Edit trigger | Selection mode — select 1 org, "Rename" button in selection bar |
| After rename tap | Exits selection mode, opens edit modal |
| Modal style | Existing pattern: bottom sheet (mobile), centered dialog (desktop) |

## Part 1: UI Refresh

### New design token

Add `shadow-ds-card` in `app.css`:

```css
.shadow-ds-card {
  box-shadow: 0 1px 3px rgba(11, 28, 48, 0.08), 0 4px 12px rgba(11, 28, 48, 0.04);
}
```

### Organization index changes

- Page container: `bg-ds-surface-low` → `bg-white`
- Org cards: add `shadow-ds-card` class
- All other card styles unchanged (`bg-ds-surface-card`, `rounded-ds-sharp`, `hover:bg-ds-surface-highest`)

### Family index changes

- Page container: `bg-ds-surface-low` → `bg-white`
- Toolbar background: `bg-ds-surface-low` → `bg-white` (toolbar div at line 3 also uses `bg-ds-surface-low`)
- Family cards: add `shadow-ds-card` class
- All other card styles unchanged

### DESIGN.md updates

Add to Visual system section:
- Index/grid pages use white (`bg-white`) page background
- Cards use `shadow-ds-card` for grounded elevation
- `shadow-ds-ambient` is reserved for floating layers (modals, popovers, drawers)

### COMPONENTS.jsonl update

Append new decision documenting the card shadow pattern.

## Part 2: Rename Organization

### UI behavior

1. Admin enters selection mode (existing toggle)
2. Selects exactly one organization
3. Selection bar shows "Rename" button alongside "Delete"
   - "Rename" only visible when `MapSet.size(selected_ids) == 1`
   - "Rename" only visible when `can?(current_scope, :update, Organization)`
4. Tapping "Rename":
   - Exits selection mode (clears `selected_ids`, sets `selection_mode` to false)
   - Opens rename modal with pre-filled name
5. Modal: single name input, Save/Cancel buttons
6. Save calls `Organizations.update_organization/2`
7. On success: close modal, `stream_insert(:organizations, updated_org)` to update the card in place, flash message
8. On cancel/escape: close modal, return to normal browsing

### State changes in `OrganizationLive.Index`

New assigns (initialize all in `mount/3`):
- `show_rename_modal` — boolean, default `false`
- `rename_form` — changeset-backed form, default `nil`
- `rename_org` — the org being renamed, default `nil`

New event handlers:
- `rename_selected` — extracts the single ID from `selected_ids`, fetches via `get_organization!/1`, builds changeset form, exits selection mode, opens modal
- `validate_rename` — validates changeset on each keystroke
- `save_rename` — persists via `Organizations.update_organization/2`, closes modal, updates stream
- `cancel_rename` — closes modal, clears rename state

### Modal template

Follows the exact same inline modal pattern as the existing create modal:
- Container: `fixed inset-0 z-50 flex items-end lg:items-center justify-center`
- Backdrop: `absolute inset-0 bg-black/60 backdrop-blur-sm`
- Panel: `relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8`
- Escape key: `phx-window-keydown="cancel_rename" phx-key="Escape"`
- Focus: `phx-mounted={JS.focus_first()}`

### Permissions

No changes needed. Existing permissions already cover this:
- Admins: `all(Organization)` — can update
- Editors/Viewers: `read(Organization)` — cannot update
- The "Rename" button is conditionally rendered using `can?(@current_scope, :update, Organization)`

### Backend

No new context functions. Already available:
- `Organizations.update_organization(org, attrs)` — updates org
- `Organizations.change_organization(org, attrs)` — builds changeset for forms

## Testing

E2E tests in `test/user_flows/`:
- Admin selects org → sees Rename button → renames successfully → name updates in grid
- Admin selects org → opens rename modal → cancels → returns to normal state
- Admin selects org → submits empty name → sees validation error
- Non-admin in selection mode → does not see Rename button
- Admin selects multiple orgs → Rename button hidden (only Delete shown)

## Files to modify

| File | Change |
|------|--------|
| `assets/css/app.css` | Add `shadow-ds-card` utility |
| `lib/web/live/organization_live/index.ex` | Add rename assigns, event handlers |
| `lib/web/live/organization_live/index.html.heex` | White bg, card shadows, rename button in selection bar, rename modal |
| `lib/web/live/family_live/index.html.heex` | White bg, card shadows |
| `DESIGN.md` | Document white bg + shadow-ds-card as standard pattern |
| `COMPONENTS.jsonl` | Append card shadow decision |
| `test/user_flows/rename_organization_test.exs` | E2E tests for rename flow |
| `priv/gettext/es-UY/LC_MESSAGES/default.po` | Spanish translations for new strings (run `mix gettext.extract --merge`) |
