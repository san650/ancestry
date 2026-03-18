# Fix Person Edit Photo Upload

## Problem

Uploading a photo in the person edit form crashes with:

```
(ArgumentError) no uploads have been allowed on component running inside
LiveView named Web.PersonLive.Show
```

**Root cause:** `PersonFormComponent` is a LiveComponent with `phx-target={@myself}` on its form. This routes upload validation events to the component, but `allow_upload(:photo, ...)` is configured on the parent LiveView. LiveView can't find the upload config on the component and raises.

The same issue affects `PersonLive.New`.

## Solution

Convert `PersonFormComponent` from a LiveComponent to a function component. Events flow to the parent LiveView, which owns the uploads.

### Changes

**1. `Web.Shared.PersonFormComponent`**
- Replace `use Web, :live_component` with `use Web, :html`
- Remove `update/2`, all `handle_event/3` clauses
- Keep template helpers (`living_checked?/1`, `month_options/0`, `day_options/0`, `upload_error_to_string/1`)
- Export a function component that receives: `person`, `family`, `form`, `uploads`, `show_details`, `action`

**2. Template (`person_form_component.html.heex`)**
- Remove all `phx-target={@myself}` attributes
- Rename `@parent_uploads` to `@uploads`

**3. `PersonLive.New`**
- Add `handle_event` for: `validate`, `save`, `toggle_details`, `cancel_upload`, `cancel`
- Manage `@form` and `@show_details` assigns in `mount`
- Move photo processing inline into `save` handler (remove `handle_info` wrappers)
- Add private helpers: `invert_living_to_deceased/1`, `process_alternate_names/1`

**4. `PersonLive.Show`**
- Add same event handlers for form events
- Initialize `@form` and `@show_details` when entering edit mode
- Move photo processing inline into `save` handler
- Remove `handle_info` for `{:person_saved, ...}`, `{:cancel_upload, ...}`, `{:cancel_edit}`
- Add same private helpers

**5. Parent templates**
- Replace `<.live_component>` with function component call, passing all required assigns

### NOT changing

- Photo processing flow (Oban jobs, PubSub, file handling)
- Person schema/changeset
- People context
- Form HTML markup/styling
- Existing tests (event names and rendered HTML stay the same)
