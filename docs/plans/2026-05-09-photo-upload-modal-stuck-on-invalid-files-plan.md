# Photo Upload Modal Stuck on Invalid Files — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the upload modal hanging on "Uploading…" when invalid entries (wrong type / too large / too many files) sit in the queue. Valid files must persist, invalid files must surface as error rows, the modal must reach the "Upload complete with errors" state — including when the entire batch is invalid.

**Architecture:** Replace the `done?`-only gate with a settled-or-errored gate. Hook the gate into both `handle_progress/3` (for batches with at least one valid uploading entry) and `handle_event("validate", ...)` (for all-invalid batches that never trigger progress events). Snapshot per-entry and form-level errors before cancelling invalid entries; merge captured errors into `upload_results`. Single file change in `lib/web/live/gallery_live/show.ex`. Modal template needs no changes.

**Tech Stack:** Phoenix LiveView 1.8 (`auto_upload: true`, `consume_uploaded_entries/3`, `cancel_upload/3`, `upload_errors/1` and `upload_errors/2`), ExUnit + `Phoenix.LiveViewTest.file_input/3` and `render_upload/2`.

**Spec:** `docs/bugfix/specs/2026-05-09-photo-upload-modal-stuck-on-invalid-files-design.md`. Read it before starting.

**Branch:** `commands` (continuation of the galleries Bus migration). All commits land directly on this branch.

**Conventions:**
- TDD per task: write failing test → run → fail → implement → run → pass → commit.
- `mix format` before each commit.
- `mix compile --warnings-as-errors` must pass before each commit.
- Final task runs `mix precommit`.
- Commit messages follow recent log style (`Add ...`, `Fix ...`).

---

## File map

| File | Change |
|---|---|
| `lib/web/live/gallery_live/show.ex` | Modify `handle_event("validate", ...)` (line 74) and `handle_progress/3` (lines 55–71). Modify `process_uploads/1` (lines 312–379). Add `maybe_finalize/1`, `settled?/2`, `format_errors/1` private helpers. |
| `test/user_flows/photo_upload_test.exs` | Add three new test cases. |

No other files change. The modal template (`lib/web/live/gallery_live/show.html.heex`) renders error rows from `upload_results` already and needs no edits.

---

## Task 1: Failing test for mixed valid + invalid file types

This task pins the bug: a `.txt` file alongside a `.jpg` should not hang the modal.

**Files:**
- Modify: `test/user_flows/photo_upload_test.exs`

- [ ] **Step 1: Add the failing test**

The existing module ends at line 99 with a single `end`. Insert the
new test just before that final `end`:

```elixir
  test "mixed valid + invalid file types — modal finalises with one error row, valid file persists",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    upload =
      file_input(view, "#upload-form", :photos, [
        %{
          name: "valid.jpg",
          content: File.read!("test/fixtures/test_image.jpg"),
          type: "image/jpeg"
        },
        %{
          name: "invalid.txt",
          content: "not an image",
          type: "text/plain"
        }
      ])

    render_upload(upload, "valid.jpg")

    html = render(view)
    assert html =~ "Upload complete"
    assert html =~ "invalid.txt"
    assert html =~ "valid.jpg"

    assert [photo_row] = Repo.all(Photo)
    assert photo_row.original_filename == "valid.jpg"

    assert [row] = Repo.all(Log)
    assert row.command_module == "Ancestry.Commands.AddPhotoToGallery"
  end
```

- [ ] **Step 2: Run, confirm failure**

```bash
mix test test/user_flows/photo_upload_test.exs
```

Expected: this new test fails. Either `assert html =~ "Upload complete"`
(modal stuck on "Uploading…") or `[photo_row] = Repo.all(Photo)` (the
valid photo was never persisted) fails. Both confirm the bug.

- [ ] **Step 3: Replace `handle_event("validate", ...)`**

Open `lib/web/live/gallery_live/show.ex`. Locate the line:

```elixir
def handle_event("validate", _params, socket), do: {:noreply, socket}
```

Replace it with:

```elixir
def handle_event("validate", _params, socket), do: maybe_finalize(socket)
```

- [ ] **Step 4: Replace `handle_progress/3` and add `maybe_finalize/1` + `settled?/2`**

Locate the existing function `defp handle_progress(:photos, _entry, socket) do … end` (lines 55–71). Replace the entire function — `defp` line through the closing `end` — with:

```elixir
defp handle_progress(:photos, _entry, socket), do: maybe_finalize(socket)

defp maybe_finalize(socket) do
  uploads = socket.assigns.uploads.photos
  entries = uploads.entries
  form_errors = upload_errors(uploads)

  socket =
    if not socket.assigns.show_upload_modal and
         (entries != [] or form_errors != []) do
      assign(socket, :show_upload_modal, true)
    else
      socket
    end

  if (entries != [] or form_errors != []) and
       Enum.all?(entries, &settled?(uploads, &1)) do
    process_uploads(socket)
  else
    {:noreply, socket}
  end
end

defp settled?(uploads, entry),
  do: entry.done? or upload_errors(uploads, entry) != []
```

> Notes for the engineer:
> - `Enum.all?([], _)` returns `true`. So when `entries == []` but
>   `form_errors != []` (e.g. all files rejected as too-many-files
>   before admission), the gate trips immediately and `process_uploads/1`
>   runs to record the form-level error.
> - `upload_errors/1` and `upload_errors/2` are auto-imported in any
>   `use Web, :live_view` module — no alias or import needed.

- [ ] **Step 5: Replace `process_uploads/1` and add `format_errors/1`**

Locate `defp process_uploads(socket) do … end` (currently lines 312–379)
and replace the whole function (`defp` through `end`) with the
following. **The body of the `consume_uploaded_entries/3` callback
(sha256 → dedup → store_original_bytes → Bus.dispatch) is identical to
today's; copy it verbatim if needed.**

```elixir
defp process_uploads(socket) do
  gallery = socket.assigns.gallery
  uploads = socket.assigns.uploads.photos

  # 1. Snapshot per-entry validation errors *before* cancelling.
  invalid_results =
    for entry <- uploads.entries,
        not entry.done?,
        errs = upload_errors(uploads, entry),
        errs != [] do
      %{name: entry.client_name, status: :error, error: format_errors(errs)}
    end

  # 2. Snapshot form-level errors (e.g. :too_many_files) *before* cancelling.
  form_results =
    for err <- upload_errors(uploads) do
      %{name: gettext("Upload"), status: :error, error: upload_error_to_string(err)}
    end

  # 3. Cancel invalid entries so consume_uploaded_entries only sees valid ones.
  socket =
    Enum.reduce(uploads.entries, socket, fn entry, acc ->
      if entry.done?, do: acc, else: cancel_upload(acc, :photos, entry.ref)
    end)

  # 4. Existing consume + Bus.dispatch loop.
  results =
    consume_uploaded_entries(socket, :photos, fn %{path: tmp_path}, entry ->
      contents = File.read!(tmp_path)

      file_hash =
        :crypto.hash(:sha256, contents)
        |> Base.encode16(case: :lower)

      if Galleries.photo_exists_in_gallery?(gallery.id, file_hash) do
        {:ok, {:duplicate, entry.client_name}}
      else
        uuid = Ecto.UUID.generate()
        ext = ext_from_content_type(entry.client_type)
        dest_key = Path.join(["uploads", "originals", uuid, "photo#{ext}"])
        original_path = Ancestry.Storage.store_original_bytes(contents, dest_key)

        attrs = %{
          gallery_id: gallery.id,
          original_path: original_path,
          original_filename: entry.client_name,
          content_type: entry.client_type,
          file_hash: file_hash
        }

        case Ancestry.Bus.dispatch(
               socket.assigns.current_scope,
               Ancestry.Commands.AddPhotoToGallery.new!(attrs)
             ) do
          {:ok, photo} -> {:ok, {:ok, photo}}
          {:error, _, _} -> {:ok, {:error, entry.client_name}}
          {:error, _} -> {:ok, {:error, entry.client_name}}
        end
      end
    end)

  {uploaded, errored} =
    Enum.split_with(results, fn
      {:ok, _} -> true
      {:duplicate, _} -> true
      {:error, _} -> false
    end)

  uploaded_photos =
    Enum.flat_map(uploaded, fn
      {:ok, photo} -> [photo]
      {:duplicate, _} -> []
    end)

  ok_results =
    Enum.map(uploaded, fn
      {:ok, photo} -> %{name: photo.original_filename, status: :ok}
      {:duplicate, name} -> %{name: name, status: :ok}
    end)

  dispatch_error_results =
    Enum.map(errored, fn {:error, name} ->
      %{name: name, status: :error, error: gettext("Upload failed")}
    end)

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

> Notes:
> - The order in steps 1–3 matters: snapshot errors first, then cancel
>   — `cancel_upload/3` clears form-level errors and removes entries
>   from `uploads.entries`.
> - The `socket` binding is rebound by `Enum.reduce/3` to the
>   cancelled-entries socket; `gallery` is captured before the rebind,
>   and `socket.assigns.current_scope` survives the cancel calls.

- [ ] **Step 6: Verify compile + the new test passes**

```bash
mix compile --warnings-as-errors
mix test test/user_flows/photo_upload_test.exs
```

Expected: clean compile; all tests in the file pass (the existing
happy path + duplicate test must not regress; the new mixed test
passes).

- [ ] **Step 7: Format + commit**

```bash
mix format
git add lib/web/live/gallery_live/show.ex test/user_flows/photo_upload_test.exs
git commit -m "Fix upload modal hanging when invalid entries are present"
```

---

## Task 2: Test for all-invalid batch

This case proves the gate trips even when nothing is uploadable. The
fix from Task 1 hooks finalize into `handle_event("validate", ...)`
specifically for this case.

**Files:**
- Modify: `test/user_flows/photo_upload_test.exs`

- [ ] **Step 1: Add the test**

Insert just before the closing module `end`, after the Task 1 test:

```elixir
  test "all-invalid batch finalises modal with no DB writes",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    file_input(view, "#upload-form", :photos, [
      %{name: "doc.txt", content: "nope", type: "text/plain"}
    ])

    html = render(view)
    assert html =~ "Upload complete"
    assert html =~ "doc.txt"

    assert Repo.all(Photo) == []
    assert Repo.all(Log) == []
  end
```

> `file_input/3` triggers the LiveView's `validate` event before
> attempting any uploads. Because the entry is invalid, no
> `handle_progress` event ever fires — the validate-event hook from
> Task 1 is what makes this test pass.

- [ ] **Step 2: Run, confirm pass**

```bash
mix test test/user_flows/photo_upload_test.exs
```

Expected: pass with no implementation changes.

If the test fails because the modal does not finalise, fall back to
asserting against the assigns directly (the validate event must be
firing through to the LiveView, but the rendered HTML may lag):

```elixir
assigns = :sys.get_state(view.pid).socket.assigns
assert assigns.upload_results != []
assert assigns.show_upload_modal == true
```

- [ ] **Step 3: Commit**

```bash
mix format
git add test/user_flows/photo_upload_test.exs
git commit -m "Add E2E test: all-invalid upload batch finalises modal"
```

---

## Task 3: Test for too-many-files form-level error

Lead with the assigns-based assertion — `render_upload/2` blocks on a
form in errored state, so don't try to advance entries to `done?` for
this case.

**Files:**
- Modify: `test/user_flows/photo_upload_test.exs`

- [ ] **Step 1: Add the test**

Insert just before the closing module `end`, after the Task 2 test:

```elixir
  test "too-many-files surfaces form-level error row",
       %{conn: conn, org: org, family: family, gallery: gallery} do
    {:ok, view, _html} =
      live(conn, ~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")

    contents = File.read!("test/fixtures/test_image.jpg")

    # max_entries is 50 in mount/3; 51 entries trips :too_many_files.
    files =
      for i <- 1..51 do
        %{
          name: "p#{i}.jpg",
          # Vary one byte so each file has a unique sha256.
          content: contents <> <<i>>,
          type: "image/jpeg"
        }
      end

    file_input(view, "#upload-form", :photos, files)

    assigns = :sys.get_state(view.pid).socket.assigns

    assert assigns.show_upload_modal == true

    assert Enum.any?(assigns.upload_results, fn r ->
             r.status == :error and r.name == "Upload"
           end)
  end
```

> Why no rendered-HTML assertion: when `:too_many_files` is set, the
> LiveView refuses to upload any entry until the user resolves the
> error (typically by removing some files). Calling `render_upload/2`
> would block. Asserting against `upload_results` is the verifiable
> outcome — it proves the gate fired and the form-level error is
> recorded.
>
> Why no `Repo.all(Photo)` assertion: with `:too_many_files` admitted
> by the form, no entry becomes `done?` and `consume_uploaded_entries/3`
> runs over an empty queue. Photos are zero in this scenario.

- [ ] **Step 2: Run, confirm pass**

```bash
mix test test/user_flows/photo_upload_test.exs
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
mix format
git add test/user_flows/photo_upload_test.exs
git commit -m "Add E2E test: too-many-files surfaces form-level error row"
```

---

## Task 4: Final verification

- [ ] **Step 1: Run the full test suite**

```bash
mix test
```

Expected: all tests pass; no regressions in the existing photo upload tests, gallery_live tests, or user_flows tests.

- [ ] **Step 2: Run `mix precommit`**

```bash
mix precommit
```

Expected: clean compile, format clean, all tests pass.

- [ ] **Step 3: Append a learning entry**

Look at the bottom of `docs/learnings.jsonl` to confirm the format
(one JSON object per line, no trailing comma). Append the following
JSON line:

```json
{"id":"upload-progress-gate-on-invalid","tags":["liveview","uploads","silent-failure"],"title":"LiveView upload finalize gate must treat invalid entries as settled","problem":"Gating finalize on Enum.all?(entries, &.done?/1) hangs forever when any invalid entry sits in the queue with auto_upload: true; valid uploads are never persisted and the modal stays in 'Uploading' state with no error surfaced. The handle_progress callback never fires for all-invalid batches.","fix":"Settle gate is &(&1.done? or upload_errors(uploads, &1) != []). Hook finalize into both handle_progress/3 and handle_event(\"validate\", ...) so all-invalid batches still trigger it. Snapshot per-entry and form-level errors before calling cancel_upload/3 (which mutates entries), then run consume_uploaded_entries/3 on the cleaned queue, then merge captured errors into upload_results."}
```

Then read `docs/learnings.md` to confirm its row format (it should be
a markdown table). Append a new row matching the existing column
schema; e.g. for a table with columns `id | tags | title`:

```markdown
| upload-progress-gate-on-invalid | liveview, uploads, silent-failure | LiveView upload finalize gate must treat invalid entries as settled |
```

> If the column schema differs, mirror the existing rows in the
> file. Never invent columns.

- [ ] **Step 4: Commit the learning**

```bash
mix format
git add docs/learnings.jsonl docs/learnings.md
git commit -m "Document LiveView upload finalize-gate learning"
```

---

## Open follow-ups (NOT in this plan)

- Replace the `%{name, status, error}` map shape with a struct.
- Toast for form-level errors instead of an "Upload" pseudo-row in the modal.
- Drag-and-drop hook UX for the over-`max_entries` case (visual feedback before the server even sees the files).
- `data-testid` on the form-level-error modal row for stable test selectors.

---

## Notes for the executing engineer

- The bug and the fix both live entirely server-side; the JS hook in
  `show.html.heex` and the modal template need no changes.
- `handle_progress/3` only fires for entries whose bytes are uploading.
  All-invalid batches and over-`max_entries` batches do not trigger it.
  That is why the fix also hooks the gate into the validate event.
- `cancel_upload/3` may emit a follow-up progress event for the
  cancelled entry. Because `process_uploads/1` is only entered when
  every remaining entry is settled, the re-entered `maybe_finalize/1`
  sees a strict subset still satisfying `Enum.all?(settled?)` — no
  infinite loop. `consume_uploaded_entries/3` already removes consumed
  entries from `uploads.entries`, so no double-processing.
- Do not refactor unrelated code in this LiveView. The galleries Bus
  migration just landed and the file is touched by other recent commits.
