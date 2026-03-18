# Family E2E Tests Design

## Problem

After each new feature or bugfix there are regressions on different features. We need e2e tests for the most common user flows to prevent this.

## Decisions

- **All Playwright e2e tests** — even flows without JS dependencies, for consistency and future-proofing.
- **One file per user flow** — clear ownership, easy to run/debug individually, maps 1:1 to specs.
- **ex_machina for test data** — replace inline fixture functions with a shared factory. Start migrating the old pattern.
- **`data-testid` attributes** — decouple tests from implementation DOM IDs. Conditionally rendered only in dev/test via a server-side helper.

## Test Infrastructure

### ex_machina

Add `{:ex_machina, "~> 2.8", only: :test}` to `mix.exs`. Create `test/support/factory.ex`:

```elixir
defmodule Ancestry.Factory do
  use ExMachina.Ecto, repo: Ancestry.Repo

  def family_factory do
    %Ancestry.Families.Family{name: sequence(:family_name, &"Family #{&1}")}
  end

  def person_factory do
    %Ancestry.People.Person{given_name: sequence(:given_name, &"Person #{&1}"), surname: "Test"}
  end

  def gallery_factory do
    %Ancestry.Galleries.Gallery{name: sequence(:gallery_name, &"Gallery #{&1}"), family: build(:family)}
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

Import `Ancestry.Factory` into `DataCase`, `ConnCase`, and `E2ECase`.

### `data-testid` server-side helper

Create `lib/web/helpers/test_helpers.ex`:

```elixir
defmodule Web.Helpers.TestHelpers do
  @env Mix.env()

  def test_id(id) when @env in [:dev, :test] do
    [{"data-testid", id}]
  end

  def test_id(_id), do: []
end
```

Import in `html_helpers` block in the web module so it's available in all templates. Usage:

```heex
<button {test_id("family-new-btn")} phx-click="...">New Family</button>
```

Returns attribute list in dev/test, empty list in prod — attribute spreading handles both.

### `data-testid` test-side helper

Add to `E2ECase`:

```elixir
def test_id(id), do: "[data-testid='#{id}']"
```

Tests use: `|> click(test_id("family-create-btn"))` or `|> assert_has(test_id("family-name"))`.

### `data-testid` naming convention

`{entity}-{action}` or `{entity}-{element}`, e.g. `family-create-btn`, `person-form-submit`.

## Template Changes

Add `{test_id(...)}` to these templates (additive, no existing IDs removed):

**`family_live/index.html.heex`:** `family-new-btn`, `families-empty`, `family-card-{id}`

**`family_live/new.html.heex`:** `family-create-form`, `family-cover-input`

**`family_live/show.html.heex`:** `family-name`, `family-back-btn`, `family-edit-btn`, `family-delete-btn`, `family-edit-form`, `family-edit-save-btn`, `family-delete-modal`, `family-delete-confirm-btn`

**`family_live/people_list_component.html.heex`:** `person-add-btn`, `person-link-btn`, `person-list`, `person-item-{id}`, `person-link-modal`, `person-search-input`, `person-link-result-{id}`

**`person_live/new.html.heex` / `PersonFormComponent`:** `person-form`, `person-form-submit`, `person-photo-input`

## Test Files

All stored in `test/user_flows/`.

### `create_family_test.exs`

```
Given a system with no data
When the user clicks "New Family" → form displayed
When the user writes a name, selects a cover photo, clicks "Create"
  → navigated to family show page, empty state shown
When the user clicks the back arrow → family grid shown
When the user clicks the family in the grid → family show page
```

Setup: none. Flow: visit `/` → new → fill name → upload cover → submit → verify show → back → verify index → click family → verify show.

### `edit_family_test.exs`

```
Given a family
When the user clicks the family from /families → family show
When the user clicks "Edit" → edit modal shown
When the user enters new name, clicks "Save" → modal closed, name updated
```

Setup: `insert(:family)`.

### `delete_family_test.exs`

```
Given a family with some people and galleries
When the user clicks the family → family show
When the user clicks "Delete" → confirmation modal
When the user clicks "Delete" in modal
  → family deleted, people still exist, redirected to /families
```

Setup: `insert(:family)` + `insert(:gallery)` + `insert(:person)` linked to family.

### `create_person_test.exs`

```
Given an existing family
When the user navigates to /families, clicks the family → show + empty state
When the user clicks add person → new member page
When the user fills form, uploads photo, clicks "Create"
  → navigated to family show, person listed in sidebar
```

Setup: `insert(:family)`.

### `link_person_test.exs`

```
Given an existing family and a person not in the family
When the user navigates to family show → empty state
When the user clicks link people → search modal
When the user searches for the person → person appears
When the user selects the person → person added, modal closed, person in sidebar
```

Setup: `insert(:family)` + `insert(:person)` (not linked).
