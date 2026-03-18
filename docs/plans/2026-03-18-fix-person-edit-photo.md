# Fix Person Edit Photo Upload — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the photo upload crash in person edit/create forms by converting `PersonFormComponent` from a LiveComponent to a function component.

**Architecture:** The form component becomes a stateless function component. All event handlers and state (`@form`, `@show_details`) move to the parent LiveViews (`PersonLive.New` and `PersonLive.Show`). Upload ownership stays on the parents, and events route there naturally since there's no `phx-target` override.

**Tech Stack:** Phoenix LiveView, Ecto changesets, Waffle uploads, Oban jobs

---

### Task 1: Convert PersonFormComponent to function component

**Files:**
- Modify: `lib/web/live/shared/person_form_component.ex`
- Modify: `lib/web/live/shared/person_form_component.html.heex`

**Step 1: Rewrite the module**

Replace the entire `lib/web/live/shared/person_form_component.ex` with:

```elixir
defmodule Web.Shared.PersonFormComponent do
  use Web, :html

  defp living_checked?(form) do
    val = form[:deceased].value
    !(val in ["true", true])
  end

  defp month_options do
    [
      {"Jan", "1"},
      {"Feb", "2"},
      {"Mar", "3"},
      {"Apr", "4"},
      {"May", "5"},
      {"Jun", "6"},
      {"Jul", "7"},
      {"Aug", "8"},
      {"Sep", "9"},
      {"Oct", "10"},
      {"Nov", "11"},
      {"Dec", "12"}
    ]
  end

  defp day_options do
    Enum.map(1..31, fn d -> {to_string(d), to_string(d)} end)
  end

  defp upload_error_to_string(:too_large), do: "File too large (max 20MB)"
  defp upload_error_to_string(:not_accepted), do: "File type not supported"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
```

Key changes:
- `use Web, :html` instead of `use Web, :live_component`
- Remove `update/2`, all `handle_event/3` clauses, and all non-template helpers (`has_value?`, `birth_name_differs?`, `invert_living_to_deceased`, `process_alternate_names`)
- Keep only template helpers: `living_checked?/1`, `month_options/0`, `day_options/0`, `upload_error_to_string/1`
- The template in `person_form_component.html.heex` becomes the `render/1` function component automatically via the embedded template convention

**Step 2: Update the template**

In `lib/web/live/shared/person_form_component.html.heex`, make these changes:

1. Remove the outer `<div>` wrapper (function components don't need it, the parent provides context)
2. Remove `phx-target={@myself}` from the `<.form>` tag (line 5)
3. Replace all `@parent_uploads` with `@uploads` (lines 17, 29, 33, 49, 58)
4. Remove `phx-target={@myself}` from the cancel_upload button (line 49)
5. Remove `phx-target={@myself}` from the toggle_details button (line 259)
6. Remove `phx-target={@myself}` from the cancel button (line 304)

The result should be a `<.form>` with no `phx-target` — events go to the parent LiveView.

**Step 3: Compile to verify no errors**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds (may have warnings about unused aliases in parent modules, which is fine at this stage)

**Step 4: Commit**

```
git add lib/web/live/shared/person_form_component.ex lib/web/live/shared/person_form_component.html.heex
git commit -m "Convert PersonFormComponent from LiveComponent to function component"
```

---

### Task 2: Update PersonLive.New to handle form events

**Files:**
- Modify: `lib/web/live/person_live/new.ex`
- Modify: `lib/web/live/person_live/new.html.heex`

**Step 1: Rewrite PersonLive.New**

Replace the entire `lib/web/live/person_live/new.ex` with:

```elixir
defmodule Web.PersonLive.New do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:person, %Person{})
     |> assign(:form, to_form(People.change_person(%Person{})))
     |> assign(:show_details, false)
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_details", _, socket) do
    {:noreply, assign(socket, :show_details, true)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    params = invert_living_to_deceased(params)

    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params =
      params
      |> invert_living_to_deceased()
      |> process_alternate_names()

    case People.create_person(socket.assigns.family, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)
        {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family.id}")}
  end

  # --- Private helpers ---

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_dir = Path.join(["priv", "static", "uploads", "originals", uuid])
        File.mkdir_p!(dest_dir)
        dest_path = Path.join(dest_dir, "photo#{ext}")
        File.cp!(tmp_path, dest_path)
        {:ok, dest_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        socket

      [] ->
        socket
    end
  end

  defp invert_living_to_deceased(params) do
    case Map.pop(params, "living") do
      {nil, params} -> params
      {"true", params} -> Map.put(params, "deceased", "false")
      {"false", params} -> Map.put(params, "deceased", "true")
      {_, params} -> params
    end
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} -> params
      {"", params} -> params
      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end
end
```

Key changes from old version:
- `mount` now assigns `@form` and `@show_details`
- All `handle_event` clauses moved here from the component
- `save` directly calls `maybe_process_photo` + navigates (no `handle_info` indirection)
- `cancel_upload` calls `cancel_upload/3` directly (no `handle_info` indirection)
- `handle_info` clauses for `{:person_saved, ...}` and `{:cancel_upload, ...}` removed
- Helper functions `invert_living_to_deceased/1` and `process_alternate_names/1` added

**Step 2: Update the template**

Replace the `<.live_component>` call in `lib/web/live/person_live/new.html.heex` (lines 17-24) with:

```heex
    <Web.Shared.PersonFormComponent.person_form
      person={@person}
      family={@family}
      action={:new}
      uploads={@uploads}
      form={@form}
      show_details={@show_details}
    />
```

**Step 3: Run tests**

Run: `mix test test/web/live/person_live/new_test.exs`
Expected: All 8 tests pass

**Step 4: Commit**

```
git add lib/web/live/person_live/new.ex lib/web/live/person_live/new.html.heex
git commit -m "Move form event handlers from component into PersonLive.New"
```

---

### Task 3: Update PersonLive.Show to handle form events

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Add form state initialization to "edit" handler**

In `show.ex`, change the `"edit"` handler (line 36-38) to also initialize form state:

```elixir
  def handle_event("edit", _, socket) do
    person = socket.assigns.person

    extra_fields_present? =
      birth_name_differs?(person.given_name_at_birth, person.given_name) ||
        birth_name_differs?(person.surname_at_birth, person.surname) ||
        has_value?(person.nickname) ||
        has_value?(person.title) ||
        has_value?(person.suffix) ||
        (person.alternate_names != nil and person.alternate_names != [])

    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:form, to_form(People.change_person(person)))
     |> assign(:show_details, extra_fields_present?)}
  end
```

**Step 2: Add form event handlers**

Add these `handle_event` clauses after the existing `"cancel_edit"` handler (after line 42):

```elixir
  def handle_event("toggle_details", _, socket) do
    {:noreply, assign(socket, :show_details, true)}
  end

  def handle_event("validate", %{"person" => params}, socket) do
    params = invert_living_to_deceased(params)

    changeset =
      socket.assigns.person
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    params =
      params
      |> invert_living_to_deceased()
      |> process_alternate_names()

    case People.update_person(socket.assigns.person, params) do
      {:ok, person} ->
        socket = maybe_process_photo(socket, person)

        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:editing, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end
```

**Step 3: Update "cancel_edit" to also handle the form "cancel" event**

Replace the existing `"cancel_edit"` handler (lines 40-42) so it also catches `"cancel"` from the form:

```elixir
  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, :editing, false)}
  end
```

**Step 4: Remove obsolete handle_info clauses**

Remove these `handle_info` clauses (they are no longer needed since events come directly):

- `handle_info({:person_saved, person}, socket)` (lines 222-229)
- `handle_info({:cancel_upload, ref}, socket)` (lines 231-233)
- `handle_info({:cancel_edit}, socket)` (lines 235-237)

**Step 5: Add private helpers**

Add these private helpers to the module (near the other private helpers):

```elixir
  defp has_value?(nil), do: false
  defp has_value?(""), do: false
  defp has_value?(_), do: true

  defp birth_name_differs?(nil, _current), do: false
  defp birth_name_differs?("", _current), do: false
  defp birth_name_differs?(birth, current), do: birth != current

  defp invert_living_to_deceased(params) do
    case Map.pop(params, "living") do
      {nil, params} -> params
      {"true", params} -> Map.put(params, "deceased", "false")
      {"false", params} -> Map.put(params, "deceased", "true")
      {_, params} -> params
    end
  end

  defp process_alternate_names(params) do
    case Map.pop(params, "alternate_names_text") do
      {nil, params} -> params
      {"", params} -> params
      {text, params} ->
        names = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
        Map.put(params, "alternate_names", names)
    end
  end
```

**Step 6: Update the template**

In `lib/web/live/person_live/show.html.heex`, replace the `<.live_component>` call (lines 39-46) with:

```heex
      <Web.Shared.PersonFormComponent.person_form
        person={@person}
        family={@family}
        action={:edit}
        uploads={@uploads}
        form={@form}
        show_details={@show_details}
      />
```

**Step 7: Run tests**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: All 7 tests pass

**Step 8: Commit**

```
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "Move form event handlers from component into PersonLive.Show"
```

---

### Task 4: Run full test suite and precommit

**Step 1: Run all tests**

Run: `mix test`
Expected: All tests pass

**Step 2: Run precommit**

Run: `mix precommit`
Expected: Compiles (warnings-as-errors), formats, tests pass

**Step 3: Fix any issues found by precommit**

If there are compilation warnings (unused imports, etc.), fix and commit.
