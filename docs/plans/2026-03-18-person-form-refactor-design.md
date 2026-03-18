# Person Form Refactor — Design

## Goal

Improve the UI/UX of the person create/edit form with progressive disclosure and a shared LiveComponent.

## Architecture

### Shared LiveComponent: `Web.Shared.PersonFormComponent`

Location: `lib/web/live/shared/person_form_component.ex` (+ colocated `.html.heex`)

**Assigns from parent:**
- `person` — `%Person{}` (new struct for create, loaded for edit)
- `family` — `%Family{}`
- `action` — `:new` or `:edit`
- `uploads` — `@uploads` from parent (LiveView owns upload config)
- `id` — required

**Internal state:**
- `@form` — `to_form(changeset)`
- `@show_details` — boolean, auto-set to `true` if any extra fields have values

**Communication to parent (via `send/2`):**
- `{:person_saved, person}` on successful create/update
- `{:cancel_upload, ref}` for upload cancellation (parent owns `cancel_upload/3`)
- `{:cancel_edit}` when cancel is clicked in edit mode

## Form Layout

### Compact form (default)

```
Photo:       [file input] or [thumbnail + file input]
Given names: [____________]
   Surname:  [____________]
    Gender:  (*) Female ( ) Male ( ) Other
Birth date:  [Day v] [Month v] [Year____]
             [x] This person is living
Death date:  [Day v] [Month v] [Year____]   ← only if living unchecked

             _Add more details_
```

### Expanded form (after clicking "Add more details" or auto-expanded)

```
Photo:                [file input / thumbnail]
Given names:          [____________]
Given names at birth: [____________]
Nickname:             [____________]
Title:                [____]  Suffix: [____]   ← side by side
Surname:              [____________]
Surname at birth:     [____________]
Gender:               (*) Female ( ) Male ( ) Other
Birth date:           [Day v] [Month v] [Year____]
                      [x] This person is living
Death date:           [Day v] [Month v] [Year____]

─────────────────────────────────────
Alternate Names (Also known as — one per line)
[textarea]
```

### Auto-expand logic

On `update/2`, if any of `given_name_at_birth`, `surname_at_birth`, `nickname`, `title`, `suffix`, or `alternate_names` have non-nil/non-empty values, set `@show_details = true`. Once expanded, cannot collapse.

## Field Details

### Gender
Custom radio group — three inline radio inputs with labels. Values: `female`, `male`, `other`. Raw HTML radios styled with Tailwind (no `<.input>` since it lacks radio type).

### Living checkbox
Standard `<.input type="checkbox">` with label "This person is living". Inverts the `deceased` schema field:
- Checked → `deceased: false`
- Unchecked → `deceased: true`

Inversion handled by rendering `checked={!(@form[:deceased].value in ["true", true])}` and converting in event handlers.

### Date fields
- **Day:** `<select>` with options 1-31, blank prompt "Day"
- **Month:** `<select>` with abbreviated month names (Jan-Dec) mapping to values 1-12, blank prompt "Month"
- **Year:** `<input type="number" min="1000" max="2100">` with placeholder "Year"

All three inline in a flex row.

### Death date
Only rendered when living checkbox is unchecked (deceased is truthy).

### Title/Suffix
Side by side in a single row using `grid-cols-2` on desktop, stacking on mobile.

### Alternate names
Raw `<textarea>` with `name="person[alternate_names_text]"`. Splitting by newline on save (existing logic). Pre-populated with `Enum.join(person.alternate_names, "\n")` on edit.

### Photo
Parent's `@uploads.photo` passed to component. Component renders `<.live_file_input>`, preview with progress, and cancel button. Cancel sends `{:cancel_upload, ref}` to parent.

## Parent Integration

### PersonLive.New
- Mount: assigns `family`, `person` (`%Person{}`), `allow_upload(:photo, ...)`
- Template: toolbar + `PersonFormComponent` with `action={:new}`
- Handles `{:person_saved, person}` → navigates to `/families/:family_id`
- Handles `{:cancel_upload, ref}` → `cancel_upload(socket, :photo, ref)`

### PersonLive.Show
- Detail view and relationships unchanged
- When `@editing`, renders `PersonFormComponent` with `action={:edit}`
- Handles `{:person_saved, person}` → updates `@person`, sets `@editing = false`
- Handles `{:cancel_upload, ref}` → `cancel_upload(socket, :photo, ref)`
- Handles `{:cancel_edit}` → sets `@editing = false`

### Component invocation
```elixir
<.live_component
  module={Web.Shared.PersonFormComponent}
  id="person-form"
  person={@person}
  family={@family}
  action={:new}
  uploads={@uploads}
/>
```

## Styling

### Desktop label alignment
CSS grid with two columns (`md:grid md:grid-cols-[auto_1fr] md:gap-x-4 md:items-center`). Labels right-aligned with `md:text-right`.

### Mobile
Single column, labels stacked above inputs.

### "Add more details" link
`text-sm text-primary/60 hover:text-primary cursor-pointer` with underline, aligned to the input column. Hidden once expanded.

### Action buttons
"Create" (new) or "Save" (edit) + "Cancel". Full-width stacked on mobile, side-by-side on desktop, aligned to input column.

### General
Raw Tailwind classes throughout. No additional DaisyUI components beyond what core_components already uses.
