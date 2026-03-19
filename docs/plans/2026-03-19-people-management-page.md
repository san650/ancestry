# People Management Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `/families/:family_id/people` page that lists family members in a searchable table with read/edit modes and bulk removal.

**Architecture:** New `Web.PeopleLive.Index` LiveView using streams. New `People.list_people_for_family_with_relationship_counts/1` query function. E2E tests following existing user flow patterns.

**Tech Stack:** Phoenix LiveView, Ecto (left join + group by for relationship counts), streams, ExMachina factories, PhoenixTest.Playwright for E2E tests.

---

### Task 1: Add relationship count query to People context

**Files:**
- Modify: `lib/ancestry/people.ex`
- Test: `test/ancestry/people_test.exs`

**Step 1: Write the failing test**

Add to `test/ancestry/people_test.exs`:

```elixir
describe "list_people_for_family_with_relationship_counts/1" do
  test "returns people with their relationship count within the family" do
    family = insert(:family)
    alice = insert(:person, given_name: "Alice", surname: "Smith")
    bob = insert(:person, given_name: "Bob", surname: "Smith")
    charlie = insert(:person, given_name: "Charlie", surname: "Smith")

    for p <- [alice, bob, charlie], do: Ancestry.People.add_to_family(p, family)

    # alice is parent of bob, and partner of charlie = 2 relationships
    Ancestry.Relationships.create_relationship(alice, bob, "parent")
    Ancestry.Relationships.create_relationship(alice, charlie, "partner")

    # charlie has 1 relationship (partner of alice)
    # bob has 1 relationship (child of alice)

    results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id)

    assert length(results) == 3

    alice_result = Enum.find(results, fn {p, _} -> p.id == alice.id end)
    bob_result = Enum.find(results, fn {p, _} -> p.id == bob.id end)
    charlie_result = Enum.find(results, fn {p, _} -> p.id == charlie.id end)

    assert {_, 2} = alice_result
    assert {_, 1} = bob_result
    assert {_, 1} = charlie_result
  end

  test "returns 0 count for people with no relationships in the family" do
    family = insert(:family)
    alice = insert(:person, given_name: "Alice", surname: "Loner")
    Ancestry.People.add_to_family(alice, family)

    [{person, count}] = Ancestry.People.list_people_for_family_with_relationship_counts(family.id)

    assert person.id == alice.id
    assert count == 0
  end

  test "does not count relationships where the other person is outside the family" do
    family = insert(:family)
    alice = insert(:person, given_name: "Alice", surname: "Smith")
    outsider = insert(:person, given_name: "Outsider", surname: "Jones")

    Ancestry.People.add_to_family(alice, family)
    # outsider is NOT in the family
    Ancestry.Relationships.create_relationship(alice, outsider, "parent")

    [{person, count}] = Ancestry.People.list_people_for_family_with_relationship_counts(family.id)

    assert person.id == alice.id
    assert count == 0
  end

  test "sorts by surname then given name" do
    family = insert(:family)
    zara = insert(:person, given_name: "Zara", surname: "Adams")
    bob = insert(:person, given_name: "Bob", surname: "Adams")
    alice = insert(:person, given_name: "Alice", surname: "Brown")

    for p <- [zara, bob, alice], do: Ancestry.People.add_to_family(p, family)

    results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id)
    names = Enum.map(results, fn {p, _} -> {p.surname, p.given_name} end)

    assert names == [{"Adams", "Bob"}, {"Adams", "Zara"}, {"Brown", "Alice"}]
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people_test.exs --seed 0`
Expected: FAIL — function `list_people_for_family_with_relationship_counts/1` undefined

**Step 3: Write minimal implementation**

Add to `lib/ancestry/people.ex` (add `alias Ancestry.Relationships.Relationship` at top):

```elixir
alias Ancestry.Relationships.Relationship

def list_people_for_family_with_relationship_counts(family_id) do
  Repo.all(
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id,
      left_join: r in Relationship,
      on:
        (r.person_a_id == p.id or r.person_b_id == p.id) and
          r.id in subquery(
            from r2 in Relationship,
              join: fm_a in FamilyMember,
              on: fm_a.person_id == r2.person_a_id and fm_a.family_id == ^family_id,
              join: fm_b in FamilyMember,
              on: fm_b.person_id == r2.person_b_id and fm_b.family_id == ^family_id,
              select: r2.id
          ),
      group_by: p.id,
      order_by: [asc: p.surname, asc: p.given_name],
      select: {p, count(r.id, :distinct)}
  )
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/people_test.exs --seed 0`
Expected: PASS

**Step 5: Commit**

```
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "feat: add list_people_for_family_with_relationship_counts/1 query"
```

---

### Task 2: Add filtered variant of the relationship count query

**Files:**
- Modify: `lib/ancestry/people.ex`
- Test: `test/ancestry/people_test.exs`

**Step 1: Write the failing test**

Add to `test/ancestry/people_test.exs`:

```elixir
describe "list_people_for_family_with_relationship_counts/2" do
  test "filters by given_name, surname, and nickname with diacritics support" do
    family = insert(:family)
    jose = insert(:person, given_name: "Jose", surname: "Garcia", nickname: "Pepe")
    maria = insert(:person, given_name: "Maria", surname: "Lopez")

    for p <- [jose, maria], do: Ancestry.People.add_to_family(p, family)

    # Search by given name
    results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "jose")
    assert length(results) == 1
    assert {p, _} = hd(results)
    assert p.id == jose.id

    # Search by surname
    results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "Lopez")
    assert length(results) == 1
    assert {p, _} = hd(results)
    assert p.id == maria.id

    # Search by nickname
    results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "Pepe")
    assert length(results) == 1
    assert {p, _} = hd(results)
    assert p.id == jose.id

    # Empty search returns all
    results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "")
    assert length(results) == 2
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people_test.exs --seed 0`
Expected: FAIL — no matching clause for arity /2

**Step 3: Write minimal implementation**

Add to `lib/ancestry/people.ex`:

```elixir
def list_people_for_family_with_relationship_counts(family_id, "") do
  list_people_for_family_with_relationship_counts(family_id)
end

def list_people_for_family_with_relationship_counts(family_id, search_term) do
  escaped =
    search_term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")

  like = "%#{escaped}%"

  Repo.all(
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id,
      left_join: r in Relationship,
      on:
        (r.person_a_id == p.id or r.person_b_id == p.id) and
          r.id in subquery(
            from r2 in Relationship,
              join: fm_a in FamilyMember,
              on: fm_a.person_id == r2.person_a_id and fm_a.family_id == ^family_id,
              join: fm_b in FamilyMember,
              on: fm_b.person_id == r2.person_b_id and fm_b.family_id == ^family_id,
              select: r2.id
          ),
      where:
        fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
          fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
          fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like),
      group_by: p.id,
      order_by: [asc: p.surname, asc: p.given_name],
      select: {p, count(r.id, :distinct)}
  )
end
```

Note: The /1 arity function must be defined ABOVE both /2 clauses in the file to avoid Elixir compilation warnings about non-grouped clauses. Reorder if needed.

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/people_test.exs --seed 0`
Expected: PASS

**Step 5: Commit**

```
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "feat: add filtered variant of relationship count query"
```

---

### Task 3: Add route and create PeopleLive.Index LiveView (read mode)

**Files:**
- Modify: `lib/web/router.ex` (add route)
- Create: `lib/web/live/people_live/index.ex` (LiveView module)
- Create: `lib/web/live/people_live/index.html.heex` (template)

**Step 1: Add the route**

In `lib/web/router.ex`, inside the `live_session :default` block, add after the kinship route:

```elixir
live "/families/:family_id/people", PeopleLive.Index, :index
```

**Step 2: Create the LiveView module**

Create `lib/web/live/people_live/index.ex`:

```elixir
defmodule Web.PeopleLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)
    people = People.list_people_for_family_with_relationship_counts(family_id)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:filter, "")
     |> assign(:editing, false)
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_remove, false)
     |> assign(:people_empty?, people == [])
     |> stream(:people, people)}
  end

  @impl true
  def handle_event("filter", %{"filter" => query}, socket) do
    family_id = socket.assigns.family.id
    people = People.list_people_for_family_with_relationship_counts(family_id, query)

    {:noreply,
     socket
     |> assign(:filter, query)
     |> assign(:selected, MapSet.new())
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_edit", _, socket) do
    editing = !socket.assigns.editing

    {:noreply,
     socket
     |> assign(:editing, editing)
     |> assign(:selected, MapSet.new())}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    person_id = String.to_integer(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, person_id) do
        MapSet.delete(selected, person_id)
      else
        MapSet.put(selected, person_id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_all", _, socket) do
    family_id = socket.assigns.family.id
    filter = socket.assigns.filter
    people = People.list_people_for_family_with_relationship_counts(family_id, filter)
    ids = MapSet.new(people, fn {p, _} -> p.id end)

    {:noreply, assign(socket, :selected, ids)}
  end

  def handle_event("deselect_all", _, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("request_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, true)}
  end

  def handle_event("cancel_remove", _, socket) do
    {:noreply, assign(socket, :confirm_remove, false)}
  end

  def handle_event("confirm_remove", _, socket) do
    family = socket.assigns.family
    selected = socket.assigns.selected
    count = MapSet.size(selected)

    for person_id <- selected do
      person = People.get_person!(person_id)
      People.remove_from_family(person, family)
    end

    people = People.list_people_for_family_with_relationship_counts(family.id, socket.assigns.filter)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_remove, false)
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)
     |> put_flash(:info, "Removed #{count} #{if count == 1, do: "person", else: "people"} from the family.")}
  end
end
```

**Step 3: Create the template**

Create `lib/web/live/people_live/index.html.heex`. The template should include:

- `<Layouts.app flash={@flash}>` wrapper with a `<:toolbar>` slot
- Toolbar: back arrow linking to `/families/:family_id`, title "Family Name — People", Edit/Done toggle button, and conditional "Remove from family" button
- Search input below toolbar with `phx-change="filter"` and `phx-debounce="300"`
- Table with `id="people-table"` and `phx-update="stream"`
- Each row: conditional checkbox (edit mode), photo thumbnail or avatar fallback, "Surname, Given Names", lifespan with deceased indicator, relationship count or "not connected" badge
- Empty state div
- Confirmation modal (shown when `@confirm_remove` is true)
- Use `test_id/1` attributes on key elements: `people-table`, `people-search`, `people-edit-btn`, `people-remove-btn`, `people-confirm-remove-btn`, `people-cancel-remove-btn`, `people-row-{id}`, `people-checkbox-{id}`, `people-back-btn`

Key template patterns to follow:
- Stream iteration: `<div :for={{dom_id, {person, rel_count}} <- @streams.people} id={dom_id}>`
- Empty state: `<div class="hidden only:block">` as first child of stream container
- Photo: `Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)` with fallback `<.icon name="hero-user" />`
- Modal: use the `<.modal>` component from core_components if available, otherwise a custom overlay

**Step 4: Verify the page loads**

Run: `iex -S mix phx.server` and visit `http://localhost:4000/families/<id>/people`
Expected: Page renders with the people table

**Step 5: Commit**

```
git add lib/web/router.ex lib/web/live/people_live/index.ex lib/web/live/people_live/index.html.heex
git commit -m "feat: add PeopleLive.Index with table, search, edit mode, and bulk removal"
```

---

### Task 4: Add "Manage people" button to FamilyLive.Show toolbar

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

**Step 1: Add the button**

In `lib/web/live/family_live/show.html.heex`, in the toolbar `<div class="flex items-center gap-2">` section, add before the Kinship link:

```heex
<.link
  navigate={~p"/families/#{@family.id}/people"}
  class="btn btn-ghost btn-sm"
  id="manage-people-btn"
  {test_id("family-manage-people-btn")}
>
  <.icon name="hero-users" class="w-4 h-4" /> Manage people
</.link>
```

**Step 2: Verify visually**

Run the dev server and confirm the button appears in the toolbar and navigates correctly.

**Step 3: Commit**

```
git add lib/web/live/family_live/show.html.heex
git commit -m "feat: add Manage people button to family show toolbar"
```

---

### Task 5: Write E2E tests

**Files:**
- Create: `test/user_flows/manage_people_test.exs`

**Step 1: Create the test file**

Create `test/user_flows/manage_people_test.exs`:

```elixir
defmodule Web.UserFlows.ManagePeopleTest do
  use Web.E2ECase

  # Given a family with people (some with relationships, some without, one deceased)
  # When the user navigates to /families/:family_id
  # And clicks "Manage people" in the toolbar
  # Then the people table is shown with names, lifespans, relationship counts
  # And deceased people show the "deceased" indicator
  # And unconnected people show the "not connected" tag
  #
  # When the user types in the search box
  # Then the table narrows to matching people
  #
  # When the user clicks "Edit"
  # Then checkboxes appear on each row
  #
  # When the user selects 2 people and clicks "Remove from family"
  # Then a confirmation modal appears
  #
  # When the user confirms the removal
  # Then the people are removed from the table
  # And the page stays in edit mode
  # And a flash message confirms the removal
  #
  # When the user clicks "Done"
  # Then checkboxes disappear

  setup do
    family = insert(:family, name: "Test Family")

    alice = insert(:person, given_name: "Alice", surname: "Smith", birth_year: 1950, death_year: 2020, deceased: true)
    bob = insert(:person, given_name: "Bob", surname: "Smith", birth_year: 1955)
    charlie = insert(:person, given_name: "Charlie", surname: "Jones", nickname: "Chuck")
    diana = insert(:person, given_name: "Diana", surname: "Williams")

    for p <- [alice, bob, charlie, diana], do: Ancestry.People.add_to_family(p, family)

    # alice is parent of bob (both in family) = 1 rel each
    Ancestry.Relationships.create_relationship(alice, bob, "parent")
    # alice and charlie are partners (both in family) = 1 more rel for alice, 1 for charlie
    Ancestry.Relationships.create_relationship(alice, charlie, "partner")
    # diana has no relationships = "not connected"

    %{family: family, alice: alice, bob: bob, charlie: charlie, diana: diana}
  end

  test "view people table with correct data", %{conn: conn, family: family} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
      |> wait_liveview()

    # Verify table shows all 4 people
    conn
    |> assert_has(test_id("people-table"))
    |> assert_has(test_id("people-table"), text: "Smith, Alice")
    |> assert_has(test_id("people-table"), text: "Smith, Bob")
    |> assert_has(test_id("people-table"), text: "Jones, Charlie")
    |> assert_has(test_id("people-table"), text: "Williams, Diana")

    # Verify deceased indicator for Alice
    conn
    |> assert_has(test_id("people-table"), text: "deceased")

    # Verify "not connected" for Diana
    conn
    |> assert_has(test_id("people-table"), text: "not connected")
  end

  test "navigate from family show via toolbar", %{conn: conn, family: family} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("family-manage-people-btn"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("people-table"))
  end

  test "search filters the table", %{conn: conn, family: family} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
      |> wait_liveview()

    # Search for "Smith" — should show Alice and Bob
    conn = PhoenixTest.Playwright.type(conn, test_id("people-search") <> " input", "Smith")

    conn =
      conn
      |> assert_has(test_id("people-table"), text: "Smith, Alice", timeout: 5_000)
      |> assert_has(test_id("people-table"), text: "Smith, Bob")
      |> refute_has(test_id("people-table"), text: "Jones, Charlie")
      |> refute_has(test_id("people-table"), text: "Williams, Diana")
  end

  test "edit mode, select, and remove people", %{conn: conn, family: family, charlie: charlie, diana: diana} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
      |> wait_liveview()

    # Enter edit mode
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()

    # Checkboxes should appear
    conn =
      conn
      |> assert_has(test_id("people-checkbox-#{charlie.id}"))
      |> assert_has(test_id("people-checkbox-#{diana.id}"))

    # Select Charlie and Diana
    conn =
      conn
      |> click(test_id("people-checkbox-#{charlie.id}"))
      |> click(test_id("people-checkbox-#{diana.id}"))

    # Click remove
    conn =
      conn
      |> click(test_id("people-remove-btn"))
      |> wait_liveview()

    # Confirmation modal should appear
    conn =
      conn
      |> assert_has(test_id("people-confirm-remove-btn"))

    # Confirm removal
    conn =
      conn
      |> click(test_id("people-confirm-remove-btn"))
      |> wait_liveview()

    # Charlie and Diana should be gone, Alice and Bob remain
    conn =
      conn
      |> assert_has(test_id("people-table"), text: "Smith, Alice", timeout: 5_000)
      |> assert_has(test_id("people-table"), text: "Smith, Bob")
      |> refute_has(test_id("people-table"), text: "Jones, Charlie")
      |> refute_has(test_id("people-table"), text: "Williams, Diana")

    # Should still be in edit mode (checkboxes visible)
    conn
    |> assert_has(test_id("people-edit-btn"), text: "Done")
  end
end
```

**Step 2: Run the tests**

Run: `mix test test/user_flows/manage_people_test.exs`
Expected: All tests PASS

**Step 3: Commit**

```
git add test/user_flows/manage_people_test.exs
git commit -m "test: add E2E tests for people management page"
```

---

### Task 6: Run precommit and fix issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (compile warnings-as-errors, format, tests)

**Step 2: Fix any issues**

Address any compilation warnings, formatting issues, or test failures.

**Step 3: Final commit if needed**

```
git add -A
git commit -m "chore: fix precommit issues"
```
