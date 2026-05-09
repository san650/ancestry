# Photo upload modal stuck when invalid files are present

**Status:** Design — pending implementation plan
**Date:** 2026-05-09
**Branch:** `commands` (continuation)

## Bug

When the user drags-and-drops files into a gallery and the batch contains
invalid entries (wrong file type, file too large) — or when the user
exceeds the `max_entries` limit (50) — the upload modal opens, valid
files reach 100 % progress, but the modal never transitions to its
"Upload complete" state. The valid files that did upload to the LiveView
process are never persisted to the database and never appear in the
gallery grid.

### Root cause

`lib/web/live/gallery_live/show.ex:55-71` (`handle_progress/3`) finalises
the upload only when

```elixir
Enum.all?(entries, & &1.done?)
```

Phoenix LiveView marks an entry `done?` only after the file has finished
uploading to the server. Invalid entries never start uploading — they
have `entry.valid? == false` and an associated error in
`upload_errors(uploads.photos, entry)`. With `auto_upload: true`, valid
entries do reach `done?`, but the gate is forever held open by any
invalid entry sitting in the queue. Therefore:

1. `process_uploads/1` is never called.
2. `consume_uploaded_entries/3` never runs, so files already on disk
   are never moved into the originals store and no command is dispatched.
3. `upload_results` stays `[]`, so the modal renders the "Uploading…"
   header forever.

The `:too_many_files` form-level error reproduces the same behaviour:
LiveView admits the first 50 entries, marks the rest invalid, and the
gate hangs on those rejected entries.

## Expected behaviour

(Per option 1 of the triage.)

1. Valid files upload and appear in the gallery grid.
2. Invalid files are listed in the modal as errors with the reason
   ("File type not supported", "File too large", "Too many files").
3. The modal reaches the "Upload complete with errors" state with a
   working **Done** button.
4. `audit_log` records exactly one `Ancestry.Commands.AddPhotoToGallery`
   row per persisted photo.

## Approach

**Settle-or-skip gate, cancel invalid before consume.**

Replace the `done?`-only gate with a settled-or-errored gate, snapshot
invalid-entry errors and form-level errors before consuming, cancel the
invalid entries so `consume_uploaded_entries/3` only sees valid done
ones, then merge captured errors into `upload_results`.

Smallest blast radius: only `handle_progress/3` and `process_uploads/1`
in a single file change. No new state. Reuses the existing
`upload_error_to_string/1` helper and the modal's current error-row
template.

### Rejected alternatives

- **Eager cancel on `validate`** — drops invalid files silently before
  the user sees them in the modal. Doesn't satisfy the chosen UX.
- **Manual finalize button** — adds an extra click to the happy path
  and a visible UI change for a bug fix.

## Implementation

### `handle_progress/3`

```elixir
defp handle_progress(:photos, _entry, socket) do
  uploads = socket.assigns.uploads.photos
  entries = uploads.entries

  socket =
    if not socket.assigns.show_upload_modal and entries != [] do
      assign(socket, :show_upload_modal, true)
    else
      socket
    end

  if entries != [] and Enum.all?(entries, &settled?(uploads, &1)) do
    process_uploads(socket)
  else
    {:noreply, socket}
  end
end

defp settled?(uploads, entry),
  do: entry.done? or upload_errors(uploads, entry) != []
```

### `process_uploads/1`

Insert two snapshots and a cancel pass before the existing
`consume_uploaded_entries/3`:

```elixir
defp process_uploads(socket) do
  uploads = socket.assigns.uploads.photos

  invalid_results =
    for entry <- uploads.entries,
        not entry.done?,
        errs = upload_errors(uploads, entry),
        errs != [] do
      %{name: entry.client_name, status: :error, error: format_errors(errs)}
    end

  form_results =
    for err <- upload_errors(uploads) do
      %{name: gettext("Upload"), status: :error, error: upload_error_to_string(err)}
    end

  socket =
    Enum.reduce(uploads.entries, socket, fn entry, acc ->
      if entry.done?, do: acc, else: cancel_upload(acc, :photos, entry.ref)
    end)

  # … existing consume_uploaded_entries + Bus.dispatch loop …

  upload_results =
    invalid_results ++ form_results ++ ok_results ++ dispatch_error_results

  socket =
    socket
    |> assign(:upload_results, upload_results)
    |> assign(:show_upload_modal, true)

  {:noreply, Enum.reduce(uploaded_photos, socket, &stream_insert(&2, :photos, &1))}
end

defp format_errors(errs),
  do: errs |> Enum.map(&upload_error_to_string/1) |> Enum.join("; ")
```

### Existing code preserved

- `Ancestry.Bus.dispatch/2` loop and result classification — unchanged.
- `stream_insert/3` for newly persisted photos — unchanged.
- `upload_error_to_string/1` translation table — unchanged.
- The modal template — unchanged (it already renders error rows in
  `upload_results`).

## Edge cases

| Scenario | Result |
|---|---|
| All-invalid drop (e.g. 3 PDFs) | Gate trips immediately, modal jumps straight to "Upload complete with errors" with three error rows. No DB writes. |
| Too many files (51 of valid type) | First 50 admitted and persisted, form-level `:too_many_files` row appears in the modal alongside the 50 successes. |
| Mixed batch (4 valid + 1 invalid) | 4 successes + 1 error row. |
| All-valid happy path | `Enum.all?(settled?)` reduces to `Enum.all?(done?)`. No regression. |
| Per-entry dispatch failure | Existing `{:error, _, _}` clause already produces an error row tagged with `entry.client_name`. Preserved. |

## Testing

Three new cases in `test/user_flows/photo_upload_test.exs`, mirroring
the existing happy-path test:

| Test | Setup | Assertions |
|---|---|---|
| invalid file type produces error row + valid file uploads | upload one `.txt` + one `.jpg` via `file_input/3` | `Repo.all(Photo)` has the jpg, `assigns.upload_results` has one `:ok` row and one `:error` row, exactly one `audit_log` row |
| all-invalid batch finalises the modal | upload one `.txt` | no `Photo`, no `audit_log` row, `assigns.upload_results` has one error row, modal reaches "complete" state |
| too-many-files surfaces a form-level error row | upload 51 valid files | 50 photos persisted, `assigns.upload_results` contains a form-level `:too_many_files` error row |

Each test asserts the modal finalised by checking `upload_results != []`.

## Files changed

- `lib/web/live/gallery_live/show.ex` — `handle_progress/3` and
  `process_uploads/1` only.
- `test/user_flows/photo_upload_test.exs` — three new test cases.

## Out of scope

- Changing `max_entries` or `max_file_size`.
- Drag-and-drop JS hook (`drag-overlay`) — works correctly, only the
  server-side finalisation gate is broken.
- Refactoring `upload_results` into a struct — keep the existing
  `%{name, status, error}` map shape used by the template.
