# Create Organization Modal — Design Spec

## Overview

Add a "New Organization" button to the OrganizationLive.Index toolbar that opens an inline modal with a form to create a new organization. On success, the new organization appears in the grid and the modal closes.

## Approach

Inline modal in `OrganizationLive.Index`, toggled by an assign. This follows the existing modal pattern (e.g., delete confirmation in FamilyLive.Index) and avoids creating a separate page for a single-field form.

## Files Modified

- `lib/web/live/organization_live/index.ex` — Add assigns, event handlers
- `lib/web/live/organization_live/index.html.heex` — Add toolbar button and modal markup
- `test/user_flows/create_organization_test.exs` — User flow test (new file)

## LiveView State & Events

### New assigns in `mount/3`

| Assign | Type | Default | Purpose |
|--------|------|---------|---------|
| `@show_create_modal` | boolean | `false` | Toggles the modal visibility |
| `@form` | Phoenix form | `to_form(change_organization(%Organization{}))` | Form for the name input |

### Event handlers

| Event | Trigger | Behavior |
|-------|---------|----------|
| `"new_organization"` | Toolbar button click | Sets `@show_create_modal = true`, resets `@form` to fresh changeset |
| `"cancel_create"` | Cancel button or backdrop click | Sets `@show_create_modal = false`, resets form |
| `"validate"` | Form change | Runs changeset validation, updates `@form` with errors |
| `"save"` | Form submit | Calls `Organizations.create_organization/1`. On success: streams new org (appends to end of grid), closes modal, sets flash `:info, "Organization created"`. On error: updates `@form` with errors |

## Template Changes

### Toolbar

Add a "New Organization" button alongside the existing title, styled consistently with the FamilyLive.Index toolbar button pattern.

### Modal

Conditionally rendered when `@show_create_modal` is true:

- Fixed overlay (`inset-0 z-50`) with blurred dark backdrop (`bg-black/60 backdrop-blur-sm`)
- Backdrop click triggers `"cancel_create"` for click-away dismissal
- Centered card with `id="create-organization-modal"`
- `<.form>` with `phx-change="validate"` and `phx-submit="save"` containing:
  - `<.input field={@form[:name]} autofocus>` for the organization name
  - Cancel button (triggers `"cancel_create"`)
  - Submit button with `phx-disable-with="Creating..."`

## Design Decisions

- **Duplicate names allowed:** No uniqueness constraint exists on organization names. This is acceptable for now — if needed, it can be added in a separate migration.
- **Stream insertion position:** New org appends to the end of the grid (default `stream_insert`), not in alphabetical position. Acceptable for initial implementation.

## Testing

User flow test at `test/user_flows/create_organization_test.exs`.

### Test cases

**Given** a system with existing organizations
**When** the user is on the organizations index page and clicks "New Organization"
**Then** the create modal appears

**When** the user submits the form without a name
**Then** validation errors are shown

**When** the user enters a name and submits
**Then** the modal closes and the new organization appears in the grid

**When** the user clicks the backdrop
**Then** the modal closes without creating anything

**When** the user clicks the Cancel button
**Then** the modal closes without creating anything

**When** the user opens the modal, types a partial name, cancels, then reopens
**Then** the form is empty (no stale input or errors)
