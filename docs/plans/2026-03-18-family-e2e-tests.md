# Family E2E Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 5 Playwright e2e tests covering core family user flows, with ex_machina factories and `data-testid` infrastructure.

**Architecture:** Each test is a single Playwright test file in `test/user_flows/` using `Web.E2ECase`. A server-side `test_id/1` helper conditionally emits `data-testid` attributes (dev/test only). Tests target these attributes via a `test_id/1` CSS selector helper in `E2ECase`.

**Tech Stack:** PhoenixTest.Playwright, ExMachina, Phoenix LiveView

---

### Task 1: Add ex_machina dependency

**Files:**
- Modify: `mix.exs:44` (deps list)

**Step 1: Add the dependency**

In `mix.exs`, add to the `deps` function, after the `phoenix_test_playwright` line:

```elixir
{:ex_machina, "~> 2.8", only: :test},
```

**Step 2: Fetch deps**

Run: `mix deps.get`
Expected: `ex_machina` downloaded successfully

**Step 3: Commit**

```
git add mix.exs mix.lock
git commit -m "Add ex_machina dependency for test factories"
```

---

### Task 2: Create factory module

**Files:**
- Create: `test/support/factory.ex`

**Step 1: Create the factory**

```elixir
defmodule Ancestry.Factory do
  use ExMachina.Ecto, repo: Ancestry.Repo

  def family_factory do
    %Ancestry.Families.Family{
      name: sequence(:family_name, &"Family #{&1}")
    }
  end

  def person_factory do
    %Ancestry.People.Person{
      given_name: sequence(:given_name, &"Person #{&1}"),
      surname: "Test"
    }
  end

  def gallery_factory do
    %Ancestry.Galleries.Gallery{
      name: sequence(:gallery_name, &"Gallery #{&1}"),
      family: build(:family)
    }
  end

  def photo_factory do
    %Ancestry.Galleries.Photo{
      gallery: build(:gallery),
      original_path: "test/fixtures/test_image.jpg",
      original_filename: "test.jpg",
      content_type: "image/jpeg",
      status: "processed"
    }
  end
end
```

**Step 2: Import into case modules**

Add `import Ancestry.Factory` to the `using` blocks of:

- `test/support/data_case.ex` — inside the `quote do` block, after `import Ancestry.DataCase`
- `test/support/conn_case.ex` — inside the `quote do` block, after `import Web.ConnCase`
- `test/support/e2e_case.ex` — inside the `quote do` block, after `import Web.E2ECase`

**Step 3: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 4: Commit**

```
git add test/support/factory.ex test/support/data_case.ex test/support/conn_case.ex test/support/e2e_case.ex
git commit -m "Add ex_machina factory and import into test case modules"
```

---

### Task 3: Create server-side `test_id` helper

**Files:**
- Create: `lib/web/helpers/test_helpers.ex`
- Modify: `lib/web.ex:84-101` (html_helpers function)

**Step 1: Create the helper module**

```elixir
defmodule Web.Helpers.TestHelpers do
  @moduledoc """
  Provides `test_id/1` which emits `data-testid` attributes in dev/test only.
  In production, returns an empty list so no test attributes appear in HTML.

  Usage in templates:

      <button {test_id("family-new-btn")} phx-click="...">New Family</button>
  """

  @env Mix.env()

  def test_id(id) when @env in [:dev, :test] do
    [{"data-testid", id}]
  end

  def test_id(_id), do: []
end
```

**Step 2: Import in html_helpers**

In `lib/web.ex`, inside the `html_helpers` function's `quote do` block (around line 85), add after the `import Web.CoreComponents` line:

```elixir
import Web.Helpers.TestHelpers
```

**Step 3: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 4: Commit**

```
git add lib/web/helpers/test_helpers.ex lib/web.ex
git commit -m "Add test_id/1 helper for conditional data-testid attributes"
```

---

### Task 4: Add `test_id` CSS selector helper to E2ECase

**Files:**
- Modify: `test/support/e2e_case.ex:13` (after `wait_liveview`)

**Step 1: Add the helper**

In `test/support/e2e_case.ex`, add this function after the `wait_liveview/1` function:

```elixir
@doc """
Returns a CSS attribute selector for `data-testid`.

    click(conn, test_id("family-new-btn"))
    assert_has(conn, test_id("family-name"), text: "The Smiths")
"""
def test_id(id), do: "[data-testid='#{id}']"
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 3: Commit**

```
git add test/support/e2e_case.ex
git commit -m "Add test_id/1 CSS selector helper to E2ECase"
```

---

### Task 5: Add `data-testid` attributes to family index template

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex`

**Step 1: Add attributes**

Add `{test_id(...)}` to these elements:

1. The "New Family" link (line 6) — add `{test_id("family-new-btn")}`:
```heex
<.link
  id="new-family-btn"
  {test_id("family-new-btn")}
  navigate={~p"/families/new"}
  class="btn btn-primary"
>
```

2. The empty state div (line 22) — add `{test_id("families-empty")}`:
```heex
<div
  id="families-empty"
  {test_id("families-empty")}
  class="hidden only:block col-span-full text-center py-20 text-base-content/40"
>
```

3. Each family card in the stream (line 28) — add `{test_id("family-card-#{id}")}`. Since `id` here is the stream DOM id (a string like `"families-123"`), use `family.id` instead:
```heex
<div
  :for={{id, family} <- @streams.families}
  id={id}
  {test_id("family-card-#{family.id}")}
  class="group relative card bg-base-100 shadow-sm border border-base-200 hover:shadow-md transition-all duration-200"
>
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 3: Commit**

```
git add lib/web/live/family_live/index.html.heex
git commit -m "Add data-testid attributes to family index template"
```

---

### Task 6: Add `data-testid` attributes to family new template

**Files:**
- Modify: `lib/web/live/family_live/new.html.heex`

**Step 1: Add attributes**

1. The form (line 17) — add `{test_id("family-create-form")}`:
```heex
<.form
  for={@form}
  id="new-family-form"
  {test_id("family-create-form")}
  phx-submit="save"
  phx-change="validate"
  multipart
>
```

2. The `<.live_file_input>` (line 35) — add `{test_id("family-cover-input")}`:
```heex
<.live_file_input upload={@uploads.cover} {test_id("family-cover-input")} class="file-input file-input-bordered w-full" />
```

3. The submit button (line 67) — add `{test_id("family-create-btn")}`:
```heex
<button type="submit" {test_id("family-create-btn")} class="btn btn-primary flex-1">Create</button>
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 3: Commit**

```
git add lib/web/live/family_live/new.html.heex
git commit -m "Add data-testid attributes to family new template"
```

---

### Task 7: Add `data-testid` attributes to family show template

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

**Step 1: Add attributes**

1. Back arrow link (line 5) — add `{test_id("family-back-btn")}`:
```heex
<.link
  navigate={~p"/"}
  {test_id("family-back-btn")}
  class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
>
```

2. Family name h1 (line 11) — add `{test_id("family-name")}`:
```heex
<h1 {test_id("family-name")} class="text-2xl font-bold text-base-content">{@family.name}</h1>
```

3. Edit button (line 14) — add `{test_id("family-edit-btn")}`:
```heex
<button id="edit-family-btn" {test_id("family-edit-btn")} phx-click="edit" class="btn btn-ghost btn-sm">
```

4. Delete button (line 17) — add `{test_id("family-delete-btn")}`:
```heex
<button
  id="delete-family-btn"
  {test_id("family-delete-btn")}
  phx-click="request_delete"
  class="btn btn-ghost btn-sm text-error"
>
```

5. Edit modal form (line 113) — add `{test_id("family-edit-form")}`:
```heex
<.form for={@form} id="edit-family-form" {test_id("family-edit-form")} phx-submit="save" phx-change="validate">
```

6. Edit modal save button (line 116) — add `{test_id("family-edit-save-btn")}`:
```heex
<button type="submit" {test_id("family-edit-save-btn")} class="btn btn-primary flex-1">Save</button>
```

7. Delete confirmation modal container (line 131) — add `{test_id("family-delete-modal")}`:
```heex
<div
  id="confirm-delete-family-modal"
  {test_id("family-delete-modal")}
  class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
>
```

8. Delete confirm button (line 139) — add `{test_id("family-delete-confirm-btn")}`:
```heex
<button {test_id("family-delete-confirm-btn")} phx-click="confirm_delete" class="btn btn-error flex-1">Delete</button>
```

9. Empty state "No family members yet" div (line 96) — add `{test_id("family-empty-state")}`:
```heex
<div {test_id("family-empty-state")} class="text-center text-base-content/40">
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 3: Commit**

```
git add lib/web/live/family_live/show.html.heex
git commit -m "Add data-testid attributes to family show template"
```

---

### Task 8: Add `data-testid` attributes to people list component

**Files:**
- Modify: `lib/web/live/family_live/people_list_component.ex`

This is an inline template in the `.ex` file (no separate `.html.heex`).

**Step 1: Add attributes**

1. Link existing button (line 14) — add `{test_id("person-link-btn")}`:
```heex
<button
  id="link-existing-btn"
  {test_id("person-link-btn")}
  phx-click="open_search"
  ...
```

2. Add member link (line 21) — add `{test_id("person-add-btn")}`:
```heex
<.link
  id="add-member-btn"
  {test_id("person-add-btn")}
  navigate={~p"/families/#{@family_id}/members/new"}
  ...
```

3. People list container (line 44) — add `{test_id("person-list")}`:
```heex
<div id="people-list-items" {test_id("person-list")} class="space-y-0.5 max-h-96 overflow-y-auto">
```

4. Each person item wrapper (line 49) — add `{test_id("person-item-#{person.id}")}`:
```heex
<div
  {test_id("person-item-#{person.id}")}
  class={[
    ...
```

**Step 2: Add attributes to the link-person-modal in family show template**

In `lib/web/live/family_live/show.html.heex`, around lines 203-261:

1. Link person modal container (line 208) — add `{test_id("person-link-modal")}`:
```heex
<div
  id="link-person-modal"
  {test_id("person-link-modal")}
  class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
>
```

2. Person search input (line 213) — add `{test_id("person-search-input")}`:
```heex
<input
  id="person-search-input"
  {test_id("person-search-input")}
  type="text"
  ...
```

3. Each search result button (line 229) — add `{test_id("person-link-result-#{person.id}")}`:
```heex
<button
  id={"link-person-#{person.id}"}
  {test_id("person-link-result-#{person.id}")}
  phx-click="link_person"
  ...
```

**Step 3: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 4: Commit**

```
git add lib/web/live/family_live/people_list_component.ex lib/web/live/family_live/show.html.heex
git commit -m "Add data-testid attributes to people list and link-person modal"
```

---

### Task 9: Add `data-testid` attributes to person form component

**Files:**
- Modify: `lib/web/live/shared/person_form_component.html.heex`

**Step 1: Add attributes**

1. The form (line 3) — add `{test_id("person-form")}`:
```heex
<.form
  for={@form}
  id="person-form"
  {test_id("person-form")}
  phx-submit="save"
  phx-change="validate"
  multipart
>
```

2. The `<.live_file_input>` for photo (line 35) — add `{test_id("person-photo-input")}`:
```heex
<.live_file_input
  upload={@uploads.photo}
  {test_id("person-photo-input")}
  class="file-input file-input-bordered file-input-sm w-full"
/>
```

3. The submit button (line 298) — add `{test_id("person-form-submit")}`:
```heex
<button type="submit" id="person-form-submit" {test_id("person-form-submit")} class="btn btn-primary flex-1">
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: compiles with no errors

**Step 3: Commit**

```
git add lib/web/live/shared/person_form_component.html.heex
git commit -m "Add data-testid attributes to person form component"
```

---

### Task 10: Create `test/user_flows/` directory and create family test

**Files:**
- Create: `test/user_flows/create_family_test.exs`

**Step 1: Create the test file**

```elixir
defmodule Web.UserFlows.CreateFamilyTest do
  use Web.E2ECase

  # Given a system with no data
  # When the user clicks "New Family"
  # Then the "New Family" form is displayed.
  #
  # When the user writes a name for the family
  # And selects a cover photo
  # And clicks "Create"
  # Then a new family is created
  # And the application navigates automatically to the family show page
  # And the empty state is shown
  #
  # When the user clicks the navigate back arrow in the gallery
  # Then the grid with the list of families is shown
  #
  # When the user clicks on the family shown in the grid
  # Then the user can see the family show page
  test "create a new family with cover photo and navigate back", %{conn: conn} do
    # Visit the homepage — should see empty state
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> assert_has(test_id("families-empty"))

    # Click "New Family" — should see the form
    conn =
      conn
      |> click_link(test_id("family-new-btn"), "New Family")
      |> wait_liveview()
      |> assert_has(test_id("family-create-form"))

    # Fill in the name and upload a cover photo
    conn =
      conn
      |> fill_in("Family name", with: "The Johnsons")
      |> upload_image(
        "#{test_id("family-cover-input")} input[type=file]",
        [Path.absname("test/fixtures/test_image.jpg")]
      )

    # Submit the form — should navigate to family show page
    conn =
      conn
      |> click_button("Create")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "The Johnsons")
      |> assert_has(test_id("family-empty-state"))

    # Click the back arrow — should see the family index
    conn =
      conn
      |> click(test_id("family-back-btn"))
      |> wait_liveview()
      |> refute_has(test_id("families-empty"))

    # Click the family card — should see the family show page again
    conn
    |> click_link("The Johnsons")
    |> wait_liveview()
    |> assert_has(test_id("family-name"), text: "The Johnsons")
  end
end
```

**Step 2: Run the test**

Run: `mix test test/user_flows/create_family_test.exs`
Expected: PASS

If it fails, debug with `@tag screenshot: true` or `@tag trace: :open` and adjust selectors.

**Step 3: Commit**

```
git add test/user_flows/create_family_test.exs
git commit -m "Add e2e test for create family user flow"
```

---

### Task 11: Edit family test

**Files:**
- Create: `test/user_flows/edit_family_test.exs`

**Step 1: Create the test file**

```elixir
defmodule Web.UserFlows.EditFamilyTest do
  use Web.E2ECase

  # Given a family
  # When the user clicks on the family from the /families page
  # Then the user navigates to the family show page
  #
  # When the user clicks "Edit" on the toolbar
  # Then a modal is shown to edit the family name
  #
  # When the user enters a new family name in the modal
  # And clicks "Save"
  # Then the modal closes and the family show page is visible
  # And the family name is updated
  setup do
    family = insert(:family, name: "Original Name")
    %{family: family}
  end

  test "edit family name via modal", %{conn: conn, family: family} do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Original Name")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Original Name")

    # Click Edit — modal should appear
    conn =
      conn
      |> click(test_id("family-edit-btn"))
      |> assert_has(test_id("family-edit-form"))

    # Fill in new name and save
    conn =
      conn
      |> fill_in("Family name", with: "Updated Name")
      |> click_button(test_id("family-edit-save-btn"), "Save")
      |> wait_liveview()

    # Modal should close and name should be updated
    conn
    |> refute_has(test_id("family-edit-form"))
    |> assert_has(test_id("family-name"), text: "Updated Name")
  end
end
```

**Step 2: Run the test**

Run: `mix test test/user_flows/edit_family_test.exs`
Expected: PASS

**Step 3: Commit**

```
git add test/user_flows/edit_family_test.exs
git commit -m "Add e2e test for edit family user flow"
```

---

### Task 12: Delete family test

**Files:**
- Create: `test/user_flows/delete_family_test.exs`

**Step 1: Create the test file**

```elixir
defmodule Web.UserFlows.DeleteFamilyTest do
  use Web.E2ECase

  alias Ancestry.People

  # Given a family with some people and galleries
  # When the user clicks on the family from the /families page
  # Then the user navigates to the family show page
  #
  # When the user clicks "Delete" on the toolbar
  # Then a confirmation modal is shown
  #
  # When the user clicks "Delete"
  # Then the family is deleted with all its related galleries
  # And people are not deleted, just detached from the family
  # And the user is redirected to the /families page
  setup do
    family = insert(:family, name: "Doomed Family")
    gallery = insert(:gallery, family: family, name: "Summer Photos")
    person = insert(:person, given_name: "Jane", surname: "Doe")
    People.add_to_family(person, family)
    %{family: family, gallery: gallery, person: person}
  end

  test "delete family keeps people but removes family and galleries", %{
    conn: conn,
    family: _family,
    person: person
  } do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Doomed Family")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Doomed Family")

    # Click Delete — confirmation modal should appear
    conn =
      conn
      |> click(test_id("family-delete-btn"))
      |> assert_has(test_id("family-delete-modal"))

    # Confirm deletion — should redirect to families index
    conn =
      conn
      |> click_button(test_id("family-delete-confirm-btn"), "Delete")
      |> wait_liveview()

    # Should be on families index, family should be gone
    conn
    |> assert_has(test_id("families-empty"))

    # Person should still exist in the database
    assert People.get_person!(person.id)
  end
end
```

**Step 2: Run the test**

Run: `mix test test/user_flows/delete_family_test.exs`
Expected: PASS

**Step 3: Commit**

```
git add test/user_flows/delete_family_test.exs
git commit -m "Add e2e test for delete family user flow"
```

---

### Task 13: Create person test

**Files:**
- Create: `test/user_flows/create_person_test.exs`

**Step 1: Create the test file**

```elixir
defmodule Web.UserFlows.CreatePersonTest do
  use Web.E2ECase

  # Given an existing family
  # When the user navigates to /families
  # And clicks on the existing family
  # Then the family show screen is shown
  # And the empty state can be seen
  #
  # When the user clicks the add person button
  # Then the page navigates to the new member page
  #
  # When the user fills the form with the user information
  # And uploads a photo for the user
  # And clicks "Create"
  # Then the page navigates to the family show page
  # And the new person is listed on the sidebar
  setup do
    family = insert(:family, name: "Smith Family")
    %{family: family}
  end

  test "create a new person in a family", %{conn: conn} do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Smith Family")
      |> wait_liveview()
      |> assert_has(test_id("family-empty-state"))

    # Click "Add member" button — should navigate to new member page
    conn =
      conn
      |> click(test_id("person-add-btn"))
      |> wait_liveview()
      |> assert_has(test_id("person-form"))

    # Fill in person details
    conn =
      conn
      |> fill_in("Given names", with: "Alice")
      |> fill_in("Surname", with: "Smith")

    # Upload a photo
    conn =
      conn
      |> upload_image(
        "#{test_id("person-photo-input")} input[type=file]",
        [Path.absname("test/fixtures/test_image.jpg")]
      )

    # Submit the form — should navigate back to family show
    conn =
      conn
      |> click_button(test_id("person-form-submit"), "Create")
      |> wait_liveview()

    # Person should appear in the sidebar
    conn
    |> assert_has(test_id("family-name"), text: "Smith Family")
    |> assert_has(test_id("person-list"), text: "Smith")
  end
end
```

**Step 2: Run the test**

Run: `mix test test/user_flows/create_person_test.exs`
Expected: PASS

**Step 3: Commit**

```
git add test/user_flows/create_person_test.exs
git commit -m "Add e2e test for create person user flow"
```

---

### Task 14: Link person test

**Files:**
- Create: `test/user_flows/link_person_test.exs`

**Step 1: Create the test file**

```elixir
defmodule Web.UserFlows.LinkPersonTest do
  use Web.E2ECase

  # Given an existing family
  # And an existing person that's not associated to the family
  # When the user navigates to /families
  # And clicks on the existing family
  # Then the family show screen is shown
  # And the empty state can be seen
  #
  # When the user clicks the link people button
  # Then a modal is shown to search for an existing person
  #
  # When the user searches the existing user in the search form
  # Then the user appears as an option
  #
  # When the user selects the person from the search form
  # Then the person is added to the family
  # And the page navigates to the family show page
  # And the new person is listed on the sidebar
  setup do
    family = insert(:family, name: "Jones Family")
    person = insert(:person, given_name: "Bob", surname: "Williams")
    %{family: family, person: person}
  end

  test "link an existing person to a family", %{conn: conn, person: person} do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Jones Family")
      |> wait_liveview()
      |> assert_has(test_id("family-empty-state"))

    # Click "Link existing person" button — modal should appear
    conn =
      conn
      |> click(test_id("person-link-btn"))
      |> assert_has(test_id("person-link-modal"))

    # Search for the person by name
    conn =
      conn
      |> fill_in(test_id("person-search-input"), with: "Bob")

    # Wait for debounced search results — person should appear
    conn =
      conn
      |> assert_has(test_id("person-link-result-#{person.id}"), timeout: 5_000)

    # Click the search result to link the person
    conn =
      conn
      |> click(test_id("person-link-result-#{person.id}"))
      |> wait_liveview()

    # Modal should close and person should be in the sidebar
    conn
    |> refute_has(test_id("person-link-modal"))
    |> assert_has(test_id("person-list"), text: "Williams")
  end
end
```

**Step 2: Run the test**

Run: `mix test test/user_flows/link_person_test.exs`
Expected: PASS

**Step 3: Commit**

```
git add test/user_flows/link_person_test.exs
git commit -m "Add e2e test for link person user flow"
```

---

### Task 15: Run full test suite and verify

**Step 1: Run all user flow tests**

Run: `mix test test/user_flows/`
Expected: All 5 tests pass

**Step 2: Run the full test suite**

Run: `mix precommit`
Expected: All tests pass, no warnings, code formatted

**Step 3: Final commit if any formatting changes**

```
git add -A
git commit -m "Format code after precommit"
```
