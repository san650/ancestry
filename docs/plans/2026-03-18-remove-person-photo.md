# Remove Person Photo — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Remove" link next to the person photo in the edit form that clears the photo from the DB and deletes files on disk.

**Architecture:** Add `People.remove_photo/1` context function, a "Remove" link in the form template, and a `handle_event("remove_photo", ...)` in `PersonLive.Show`.

**Tech Stack:** Phoenix LiveView, Ecto, Waffle (file cleanup)

---

### Task 1: Add `remove_photo/1` to the People context

**Files:**
- Modify: `lib/ancestry/people.ex:147-152`

**Step 1: Add the function**

Add `remove_photo/1` right before the existing `cleanup_person_files/1` private function (line 149 in `people.ex`):

```elixir
  def remove_photo(%Person{} = person) do
    result =
      person
      |> Ecto.Changeset.change(%{photo: nil, photo_status: nil})
      |> Repo.update()

    case result do
      {:ok, person} ->
        cleanup_person_files(person)
        {:ok, person}

      error ->
        error
    end
  end
```

This clears the DB fields first, then deletes files on disk. The `cleanup_person_files/1` helper already exists and does `File.rm_rf` on the person's photo directory.

**Step 2: Compile**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

**Step 3: Commit**

```
git add lib/ancestry/people.ex
git commit -m "Add People.remove_photo/1 context function"
```

---

### Task 2: Add "Remove" link to the form template

**Files:**
- Modify: `lib/web/live/shared/person_form_component.html.heex:16-25`

**Step 1: Update the photo display block**

Replace the current photo display block (lines 16-25) with a version that includes a "Remove" link:

```heex
          <%= if @action == :edit && @person.photo && @person.photo_status == "processed" && @uploads.photo.entries == [] do %>
            <div class="mb-3 flex items-center gap-3">
              <img
                src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
                alt="Current photo"
                class="w-16 h-16 rounded-lg object-cover"
              />
              <span class="text-sm text-base-content/50">Current photo</span>
              <button
                type="button"
                id="remove-photo-btn"
                phx-click="remove_photo"
                class="text-sm text-error/70 hover:text-error transition-colors"
              >
                Remove
              </button>
            </div>
          <% end %>
```

The only addition is the `<button>` with `id="remove-photo-btn"` and `phx-click="remove_photo"`. No `phx-target` needed since this is a function component — events go to the parent LiveView.

**Step 2: Compile**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation

**Step 3: Commit**

```
git add lib/web/live/shared/person_form_component.html.heex
git commit -m "Add Remove button next to current person photo in edit form"
```

---

### Task 3: Add handle_event to PersonLive.Show

**Files:**
- Modify: `lib/web/live/person_live/show.ex:97-99`

**Step 1: Add the event handler**

Add this `handle_event` clause after the existing `"cancel_upload"` handler (after line 99 in `show.ex`):

```elixir
  def handle_event("remove_photo", _, socket) do
    case People.remove_photo(socket.assigns.person) do
      {:ok, person} ->
        {:noreply,
         socket
         |> assign(:person, person)
         |> assign(:form, to_form(People.change_person(person)))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove photo")}
    end
  end
```

Key details:
- Stays in edit mode (`@editing` is not changed)
- Updates both `@person` (so the template condition hides the photo) and `@form` (so the form reflects the updated person)
- On error, shows a flash message

**Step 2: Run tests**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: All existing tests still pass

**Step 3: Commit**

```
git add lib/web/live/person_live/show.ex
git commit -m "Handle remove_photo event in PersonLive.Show"
```

---

### Task 4: Add test for photo removal

**Files:**
- Modify: `test/web/live/person_live/show_test.exs`

**Step 1: Add test**

Add this test to the existing `Web.PersonLive.ShowTest` module:

```elixir
  test "removes person photo from edit form", %{conn: conn, family: family, person: person} do
    # Given a person with a processed photo
    {:ok, person_with_photo} =
      person
      |> Ecto.Changeset.change(%{
        photo: %{file_name: "test.jpg", updated_at: nil},
        photo_status: "processed"
      })
      |> Ancestry.Repo.update()

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person_with_photo.id}")

    # When the user clicks edit and then remove photo
    view |> element("#edit-person-btn") |> render_click()
    assert has_element?(view, "#remove-photo-btn")

    view |> element("#remove-photo-btn") |> render_click()

    # Then the photo is removed and the remove button is gone
    refute has_element?(view, "#remove-photo-btn")

    # And the DB is updated
    updated = People.get_person!(person.id)
    assert is_nil(updated.photo)
    assert is_nil(updated.photo_status)
  end
```

**Step 2: Run test**

Run: `mix test test/web/live/person_live/show_test.exs`
Expected: All tests pass including the new one

**Step 3: Commit**

```
git add test/web/live/person_live/show_test.exs
git commit -m "Add test for person photo removal in edit form"
```

---

### Task 5: Run precommit

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compiles clean, formats, all tests pass

**Step 2: Fix any issues found**

If formatting or warnings, fix and commit.
