# Create Family From Person — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Create subfamily" feature that creates a new family from a selected person's connected relatives (ascendants, descendants, partners) within the current family.

**Architecture:** BFS graph traversal in `Ancestry.Families` walks relationships scoped to source family members, collects person IDs, creates a new family with bulk-inserted `FamilyMember` records. The UI is a modal on `FamilyLive.Show` with a person selector (reusing `PersonSelectorComponent` with configurable event), name input, and checkbox. No new routes or schema changes.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto (PostgreSQL), existing `Ancestry.Relationships` query functions

**Spec:** `docs/superpowers/specs/2026-03-22-create-family-from-person-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `lib/ancestry/families.ex` | Add `create_family_from_person/5` + private BFS traversal functions |
| Modify | `lib/web/live/family_live/person_selector_component.ex` | Add configurable `on_select` message |
| Modify | `lib/web/live/family_live/show.ex` | Add modal assigns, event handlers, `handle_info` for person selection |
| Modify | `lib/web/live/family_live/show.html.heex` | Add toolbar button + Create Subfamily modal |
| Create | `test/ancestry/families/create_family_from_person_test.exs` | Context tests for traversal + family creation |
| Create | `test/user_flows/create_subfamily_test.exs` | E2E user flow test |

---

## Task 1: BFS Graph Traversal + Family Creation

**Files:**
- Create: `test/ancestry/families/create_family_from_person_test.exs`
- Modify: `lib/ancestry/families.ex`

### Test: Person with no relationships creates family with only themselves

- [ ] **Step 1: Write the failing test**

Create `test/ancestry/families/create_family_from_person_test.exs`:

```elixir
defmodule Ancestry.Families.CreateFamilyFromPersonTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.FamilyMember

  describe "create_family_from_person/5" do
    test "person with no relationships creates family with only themselves" do
      {org, family, person} = setup_single_person()

      assert {:ok, new_family} =
               Families.create_family_from_person(org, "New Family", person, family.id, [])

      assert new_family.name == "New Family"
      assert new_family.organization_id == org.id

      members = People.list_people_for_family(new_family.id)
      assert length(members) == 1
      assert hd(members).id == person.id
    end
  end

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    org
  end

  defp family_fixture(org, attrs \\ %{}) do
    {:ok, family} = Families.create_family(org, Enum.into(attrs, %{name: "Source Family"}))
    family
  end

  defp person_fixture(family, attrs \\ %{}) do
    {:ok, person} =
      People.create_person(
        family,
        Enum.into(attrs, %{given_name: "Test", surname: "Person"})
      )

    person
  end

  defp setup_single_person do
    org = org_fixture()
    family = family_fixture(org)
    person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
    {org, family, person}
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: FAIL — `create_family_from_person/5` is undefined

- [ ] **Step 3: Write minimal implementation**

Add to `lib/ancestry/families.ex` — add the alias for `Person` at the top, and the new function:

```elixir
alias Ancestry.People.Person
alias Ancestry.People.FamilyMember

def create_family_from_person(
      %Ancestry.Organizations.Organization{} = org,
      family_name,
      %Person{} = person,
      source_family_id,
      opts \\ []
    ) do
  Repo.transaction(fn ->
    case create_family(org, %{name: family_name}) do
      {:ok, new_family} ->
        person_ids = collect_connected_people(person.id, source_family_id, opts)

        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        members =
          Enum.map(person_ids, fn pid ->
            %{family_id: new_family.id, person_id: pid, inserted_at: now, updated_at: now}
          end)

        Repo.insert_all(FamilyMember, members)

        # Set selected person as default
        People.set_default_member(new_family.id, person.id)

        new_family

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end)
end

defp collect_connected_people(person_id, source_family_id, opts) do
  include_partner_ancestors = Keyword.get(opts, :include_partner_ancestors, false)
  bfs_traverse(MapSet.new(), [person_id], source_family_id, include_partner_ancestors)
end

defp bfs_traverse(visited, [], _family_id, _include_partner_ancestors), do: visited

defp bfs_traverse(visited, queue, family_id, include_partner_ancestors) do
  opts = [family_id: family_id]

  new_queue =
    Enum.flat_map(queue, fn person_id ->
      if MapSet.member?(visited, person_id) do
        []
      else
        parent_ids =
          Ancestry.Relationships.get_parents(person_id, opts)
          |> Enum.map(fn {person, _rel} -> person.id end)

        child_ids =
          Ancestry.Relationships.get_children(person_id, opts)
          |> Enum.map(& &1.id)

        active_partner_ids =
          Ancestry.Relationships.get_active_partners(person_id, opts)
          |> Enum.map(fn {person, _rel} -> person.id end)

        former_partner_ids =
          Ancestry.Relationships.get_former_partners(person_id, opts)
          |> Enum.map(fn {person, _rel} -> person.id end)

        all_partner_ids = active_partner_ids ++ former_partner_ids

        # Partners' parents if option is enabled
        partner_parent_ids =
          if include_partner_ancestors do
            Enum.flat_map(all_partner_ids, fn partner_id ->
              Ancestry.Relationships.get_parents(partner_id, opts)
              |> Enum.map(fn {person, _rel} -> person.id end)
            end)
          else
            []
          end

        parent_ids ++ child_ids ++ all_partner_ids ++ partner_parent_ids
      end
    end)

  new_visited = Enum.reduce(queue, visited, &MapSet.put(&2, &1))
  unvisited_queue = Enum.reject(new_queue, &MapSet.member?(new_visited, &1))

  bfs_traverse(new_visited, unvisited_queue, family_id, include_partner_ancestors)
end
```

Note: You also need to add `alias Ancestry.People` at the top of the module (alongside existing aliases).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs lib/ancestry/families.ex
git commit -m "Add create_family_from_person with BFS traversal (single person case)"
```

### Test: Traversal includes parents, children, and partners

- [ ] **Step 6: Write the failing test**

Add to the `describe "create_family_from_person/5"` block in `test/ancestry/families/create_family_from_person_test.exs`:

```elixir
test "includes parents, children, and active partners" do
  {org, family, person, parent, child, partner} = setup_full_family()

  {:ok, new_family} =
    Families.create_family_from_person(org, "New", person, family.id, [])

  member_ids = People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

  assert MapSet.member?(member_ids, person.id)
  assert MapSet.member?(member_ids, parent.id)
  assert MapSet.member?(member_ids, child.id)
  assert MapSet.member?(member_ids, partner.id)
  assert MapSet.size(member_ids) == 4
end
```

Add the helper:

```elixir
defp setup_full_family do
  org = org_fixture()
  family = family_fixture(org)
  person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
  parent = person_fixture(family, %{given_name: "Bob", surname: "Smith"})
  child = person_fixture(family, %{given_name: "Charlie", surname: "Smith"})
  partner = person_fixture(family, %{given_name: "Dave", surname: "Jones"})

  {:ok, _} = Ancestry.Relationships.create_relationship(parent, person, "parent")
  {:ok, _} = Ancestry.Relationships.create_relationship(person, child, "parent")
  {:ok, _} = Ancestry.Relationships.create_relationship(person, partner, "married")

  {org, family, person, parent, child, partner}
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS (the BFS already handles this)

- [ ] **Step 8: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add test for parent/child/partner inclusion in create_family_from_person"
```

### Test: include_partner_ancestors option

- [ ] **Step 9: Write the tests**

Add two more tests to the describe block:

```elixir
test "with include_partner_ancestors: false, partner's parents are excluded" do
  {org, family, person, _parent, _child, partner} = setup_full_family()
  partner_parent = person_fixture(family, %{given_name: "Eve", surname: "Jones"})
  {:ok, _} = Ancestry.Relationships.create_relationship(partner_parent, partner, "parent")

  {:ok, new_family} =
    Families.create_family_from_person(org, "New", person, family.id,
      include_partner_ancestors: false
    )

  member_ids = People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

  assert MapSet.member?(member_ids, partner.id)
  refute MapSet.member?(member_ids, partner_parent.id)
end

test "with include_partner_ancestors: true, partner's parents are included" do
  {org, family, person, _parent, _child, partner} = setup_full_family()
  partner_parent = person_fixture(family, %{given_name: "Eve", surname: "Jones"})
  {:ok, _} = Ancestry.Relationships.create_relationship(partner_parent, partner, "parent")

  {:ok, new_family} =
    Families.create_family_from_person(org, "New", person, family.id,
      include_partner_ancestors: true
    )

  member_ids = People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

  assert MapSet.member?(member_ids, partner.id)
  assert MapSet.member?(member_ids, partner_parent.id)
end
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add tests for include_partner_ancestors option"
```

### Test: People outside the source family are excluded

- [ ] **Step 12: Write the test**

```elixir
test "people not in source family are excluded even if they have relationships" do
  org = org_fixture()
  family = family_fixture(org)
  other_family = family_fixture(org, %{name: "Other Family"})

  person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
  outside_parent = person_fixture(other_family, %{given_name: "Bob", surname: "Smith"})

  # Create a parent relationship — but the parent is NOT in the source family
  {:ok, _} = Ancestry.Relationships.create_relationship(outside_parent, person, "parent")

  {:ok, new_family} =
    Families.create_family_from_person(org, "New", person, family.id, [])

  member_ids = People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

  assert MapSet.member?(member_ids, person.id)
  refute MapSet.member?(member_ids, outside_parent.id)
  assert MapSet.size(member_ids) == 1
end
```

- [ ] **Step 13: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS

- [ ] **Step 14: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add test for excluding people outside source family"
```

### Test: Selected person is set as default member

- [ ] **Step 15: Write the test**

```elixir
test "selected person is set as default member of the new family" do
  {org, family, person} = setup_single_person()

  {:ok, new_family} =
    Families.create_family_from_person(org, "New", person, family.id, [])

  default = People.get_default_person(new_family.id)
  assert default.id == person.id
end
```

- [ ] **Step 16: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS

- [ ] **Step 17: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add test for default member setting in create_family_from_person"
```

### Test: Partner's children from other relationships are included

- [ ] **Step 18: Write the test**

```elixir
test "partner's children from other relationships are included if in source family" do
  org = org_fixture()
  family = family_fixture(org)

  alice = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
  bob = person_fixture(family, %{given_name: "Bob", surname: "Jones"})
  # Bob's child from a prior relationship, also in this family
  carol = person_fixture(family, %{given_name: "Carol", surname: "Jones"})

  {:ok, _} = Ancestry.Relationships.create_relationship(alice, bob, "married")
  {:ok, _} = Ancestry.Relationships.create_relationship(bob, carol, "parent")

  {:ok, new_family} =
    Families.create_family_from_person(org, "New", alice, family.id, [])

  member_ids = People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

  assert MapSet.member?(member_ids, alice.id)
  assert MapSet.member?(member_ids, bob.id)
  assert MapSet.member?(member_ids, carol.id)
end
```

- [ ] **Step 19: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS

- [ ] **Step 20: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add test for partner's children inclusion"
```

### Test: Invalid family name returns error

- [ ] **Step 21: Write the test**

```elixir
test "returns error changeset when family name is blank" do
  {org, family, person} = setup_single_person()

  assert {:error, changeset} =
           Families.create_family_from_person(org, "", person, family.id, [])

  assert "can't be blank" in errors_on(changeset).name
end
```

- [ ] **Step 22: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS (the transaction rollbacks with the changeset)

- [ ] **Step 23: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add test for invalid family name in create_family_from_person"
```

### Test: Person already in multiple families can be added to the new family

- [ ] **Step 24: Write the test**

```elixir
test "person already in multiple families can be added to the new family" do
  org = org_fixture()
  family_a = family_fixture(org, %{name: "Family A"})
  family_b = family_fixture(org, %{name: "Family B"})

  person = person_fixture(family_a, %{given_name: "Alice", surname: "Smith"})
  People.add_to_family(person, family_b)

  # Person is now in family_a and family_b
  assert {:ok, new_family} =
           Families.create_family_from_person(org, "New", person, family_a.id, [])

  members = People.list_people_for_family(new_family.id)
  assert length(members) == 1
  assert hd(members).id == person.id

  # Person is now in 3 families
  person = People.get_person!(person.id)
  assert length(person.families) == 3
end
```

- [ ] **Step 25: Run test to verify it passes**

Run: `mix test test/ancestry/families/create_family_from_person_test.exs -v`
Expected: PASS

- [ ] **Step 26: Commit**

```bash
git add test/ancestry/families/create_family_from_person_test.exs
git commit -m "Add test for multi-family person in create_family_from_person"
```

---

## Task 2: Parameterize PersonSelectorComponent

**Files:**
- Modify: `lib/web/live/family_live/person_selector_component.ex`

- [ ] **Step 1: Read the current component**

Read `lib/web/live/family_live/person_selector_component.ex` to understand the current event handling.

The component currently hardcodes `send(self(), {:focus_person, String.to_integer(id)})` in the `select_person` handler. We need to make this configurable via an optional `on_select` assign that defaults to `:focus_person`.

- [ ] **Step 2: Modify the component**

In `lib/web/live/family_live/person_selector_component.ex`, change the `handle_event("select_person", ...)` function:

```elixir
# Before:
def handle_event("select_person", %{"id" => id}, socket) do
  send(self(), {:focus_person, String.to_integer(id)})
  {:noreply, assign(socket, open: false, query: "")}
end

# After:
def handle_event("select_person", %{"id" => id}, socket) do
  msg = Map.get(socket.assigns, :on_select, :focus_person)
  send(self(), {msg, String.to_integer(id)})
  {:noreply, assign(socket, open: false, query: "")}
end
```

- [ ] **Step 3: Verify existing behavior is unchanged**

Run the full test suite to confirm nothing breaks — the default `:focus_person` message preserves existing behavior:

Run: `mix test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/family_live/person_selector_component.ex
git commit -m "Parameterize PersonSelectorComponent with configurable on_select message"
```

---

## Task 3: LiveView Event Handlers

**Files:**
- Modify: `lib/web/live/family_live/show.ex`

- [ ] **Step 1: Read the current show.ex**

Read `lib/web/live/family_live/show.ex` to understand the existing mount assigns and event handler patterns.

- [ ] **Step 2: Add modal assigns to mount**

In the `mount/3` function in `lib/web/live/family_live/show.ex`, add the new assigns after the existing ones (e.g., after the `adding_relationship` assign):

```elixir
|> assign(:show_create_subfamily_modal, false)
|> assign(:subfamily_person, nil)
|> assign(:subfamily_form, to_form(Families.change_family(%Ancestry.Families.Family{})))
|> assign(:subfamily_include_partner_ancestors, false)
```

- [ ] **Step 3: Add event handlers**

Add these event handlers in `lib/web/live/family_live/show.ex` after the existing relationship handlers and before the PubSub handlers:

```elixir
# Create subfamily modal

def handle_event("open_create_subfamily", _, socket) do
  person = socket.assigns.focus_person || hd(socket.assigns.people)
  name = person.surname || ""

  {:noreply,
   socket
   |> assign(:show_create_subfamily_modal, true)
   |> assign(:subfamily_person, person)
   |> assign(:subfamily_form, to_form(Families.change_family(%Ancestry.Families.Family{}, %{name: name})))
   |> assign(:subfamily_include_partner_ancestors, false)}
end

def handle_event("close_create_subfamily", _, socket) do
  {:noreply,
   socket
   |> assign(:show_create_subfamily_modal, false)
   |> assign(:subfamily_person, nil)}
end

def handle_event("validate_subfamily", %{"family" => params}, socket) do
  changeset =
    %Ancestry.Families.Family{}
    |> Families.change_family(params)
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, :subfamily_form, to_form(changeset))}
end

def handle_event("toggle_partner_ancestors", %{"value" => value}, socket) do
  {:noreply, assign(socket, :subfamily_include_partner_ancestors, value == "true")}
end

def handle_event("save_subfamily", %{"family" => params}, socket) do
  person = socket.assigns.subfamily_person
  family = socket.assigns.family
  org = socket.assigns.organization
  include = socket.assigns.subfamily_include_partner_ancestors

  case Families.create_family_from_person(org, params["name"], person, family.id,
         include_partner_ancestors: include
       ) do
    {:ok, new_family} ->
      {:noreply,
       socket
       |> assign(:show_create_subfamily_modal, false)
       |> push_navigate(
         to: ~p"/org/#{org.id}/families/#{new_family.id}?person=#{person.id}"
       )}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :subfamily_form, to_form(changeset))}

    {:error, _reason} ->
      {:noreply,
       socket
       |> put_flash(:error, "Failed to create subfamily")
       |> assign(:show_create_subfamily_modal, false)}
  end
end
```

- [ ] **Step 4: Add handle_info for person selection**

Add a `handle_info` clause for the subfamily person selector event:

```elixir
def handle_info({:subfamily_person_selected, person_id}, socket) do
  person = find_person(socket.assigns.people, person_id)
  name = person.surname || ""

  {:noreply,
   socket
   |> assign(:subfamily_person, person)
   |> assign(:subfamily_form, to_form(Families.change_family(%Ancestry.Families.Family{}, %{name: name})))}
end
```

- [ ] **Step 5: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles without warnings

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/family_live/show.ex
git commit -m "Add create subfamily modal event handlers to FamilyLive.Show"
```

---

## Task 4: Modal Template

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

- [ ] **Step 1: Read the current template**

Read `lib/web/live/family_live/show.html.heex` to understand the toolbar and modal placement.

- [ ] **Step 2: Add toolbar button**

In `lib/web/live/family_live/show.html.heex`, add the "Create subfamily" button in the toolbar `<div class="flex items-center gap-2">` section, before the Edit button (before line 42):

```heex
<%= if @people != [] do %>
  <button
    id="create-subfamily-btn"
    phx-click="open_create_subfamily"
    class="inline-flex items-center gap-1.5 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp px-3 py-1.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
    {test_id("family-create-subfamily-btn")}
  >
    <.icon name="hero-square-2-stack" class="w-4 h-4" /> Create subfamily
  </button>
<% end %>
```

- [ ] **Step 3: Add the modal**

Add the Create Subfamily modal after the Add Relationship modal (after line 553, before `</Layouts.app>`):

```heex
<%!-- Create Subfamily Modal --%>
<%= if @show_create_subfamily_modal do %>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center"
    phx-window-keydown="close_create_subfamily"
    phx-key="Escape"
  >
    <div
      class="absolute inset-0 bg-black/60 backdrop-blur-sm"
      phx-click="close_create_subfamily"
    >
    </div>
    <div
      id="create-subfamily-modal"
      class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient rounded-ds-sharp w-full max-w-md mx-4 p-8"
      role="dialog"
      aria-modal="true"
      aria-labelledby="create-subfamily-title"
      phx-mounted={JS.focus_first()}
      {test_id("create-subfamily-modal")}
    >
      <h2
        id="create-subfamily-title"
        class="text-xl font-ds-heading font-bold text-ds-on-surface mb-6"
      >
        Create Subfamily
      </h2>

      <%!-- Person Selector --%>
      <div class="mb-4">
        <label class="label text-sm font-ds-body font-medium text-ds-on-surface mb-1 block">
          Starting person
        </label>
        <.live_component
          module={Web.FamilyLive.PersonSelectorComponent}
          id="subfamily-person-selector"
          people={@people}
          family_id={@family.id}
          focus_person={@subfamily_person}
          on_select={:subfamily_person_selected}
        />
      </div>

      <.form
        for={@subfamily_form}
        id="create-subfamily-form"
        phx-submit="save_subfamily"
        phx-change="validate_subfamily"
        {test_id("create-subfamily-form")}
      >
        <.input
          field={@subfamily_form[:name]}
          label="Family name"
          placeholder="e.g. Smith"
          {test_id("create-subfamily-name-input")}
        />

        <div class="mt-4">
          <label class="flex items-start gap-3 cursor-pointer">
            <input
              type="checkbox"
              name="include_partner_ancestors"
              value="true"
              checked={@subfamily_include_partner_ancestors}
              phx-click="toggle_partner_ancestors"
              phx-value-value={to_string(!@subfamily_include_partner_ancestors)}
              class="mt-0.5 w-4 h-4 rounded-sm border-ds-outline-variant text-ds-primary focus:ring-ds-primary"
              {test_id("create-subfamily-partner-ancestors-checkbox")}
            />
            <div>
              <span class="text-sm font-ds-body font-medium text-ds-on-surface">
                Include partners' families
              </span>
              <p class="text-xs text-ds-on-surface-variant mt-0.5">
                When checked, ascendants of partners will also be included.
              </p>
            </div>
          </label>
        </div>

        <div class="flex gap-3 mt-6">
          <button
            type="submit"
            class="flex-1 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
            phx-disable-with="Creating..."
            {test_id("create-subfamily-submit-btn")}
          >
            Create
          </button>
          <button
            type="button"
            phx-click="close_create_subfamily"
            class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
          >
            Cancel
          </button>
        </div>
      </.form>
    </div>
  </div>
<% end %>
```

- [ ] **Step 4: Verify compilation and rendering**

Run: `mix compile --warnings-as-errors`
Expected: Compiles without warnings

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/family_live/show.html.heex
git commit -m "Add Create Subfamily button and modal to family show page"
```

---

## Task 5: E2E User Flow Test

**Files:**
- Create: `test/user_flows/create_subfamily_test.exs`

- [ ] **Step 1: Write the E2E test**

Create `test/user_flows/create_subfamily_test.exs`.

**Important API notes:**
- Use `PhoenixTest.Playwright.press(conn, "body", "Escape")` to send Escape key (not `send_keys`)
- Use `click_button(test_id("selector"), "Text")` with test ID selectors to avoid ambiguous button matches

```elixir
defmodule Web.UserFlows.CreateSubfamilyTest do
  use Web.E2ECase

  # Given a family with connected people (parent, person, child)
  # When the user clicks the "Create subfamily" button on the family show page
  # Then a modal appears with the focused person pre-selected
  #
  # When the user enters a family name and clicks Create
  # Then a new family is created with the expected members
  # And the user is navigated to the new family's show page
  #
  # Given the modal is open
  # When the user presses Escape
  # Then the modal closes without creating a family

  setup do
    org = insert(:organization, name: "Test Org")
    family = insert(:family, name: "Big Family", organization: org)

    alice = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
    bob = insert(:person, given_name: "Bob", surname: "Smith", organization: org)
    charlie = insert(:person, given_name: "Charlie", surname: "Smith", organization: org)

    Ancestry.Repo.insert!(%Ancestry.People.FamilyMember{family_id: family.id, person_id: alice.id})
    Ancestry.Repo.insert!(%Ancestry.People.FamilyMember{family_id: family.id, person_id: bob.id})
    Ancestry.Repo.insert!(%Ancestry.People.FamilyMember{family_id: family.id, person_id: charlie.id})

    {:ok, _} = Ancestry.Relationships.create_relationship(bob, alice, "parent")
    {:ok, _} = Ancestry.Relationships.create_relationship(alice, charlie, "parent")

    Ancestry.People.set_default_member(family.id, alice.id)

    %{org: org, family: family, alice: alice, bob: bob, charlie: charlie}
  end

  test "create subfamily from family show page", %{
    conn: conn,
    org: org,
    family: family
  } do
    # Visit the family show page — should see the tree with Alice focused
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Big Family")

    # Click "Create subfamily" — modal should appear
    conn =
      conn
      |> click(test_id("family-create-subfamily-btn"))
      |> assert_has(test_id("create-subfamily-modal"))

    # Fill in a family name and submit
    conn =
      conn
      |> fill_in("Family name", with: "Smith Subfamily")
      |> click_button(test_id("create-subfamily-submit-btn"), "Create")
      |> wait_liveview()

    # Should navigate to the new family's show page
    conn
    |> assert_has(test_id("family-name"), text: "Smith Subfamily")
  end

  test "modal closes on Escape without creating a family", %{
    conn: conn,
    org: org,
    family: family
  } do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("family-create-subfamily-btn"))
      |> assert_has(test_id("create-subfamily-modal"))

    # Press Escape — modal should close
    conn =
      conn
      |> PhoenixTest.Playwright.press("body", "Escape")

    conn
    |> refute_has(test_id("create-subfamily-modal"))
    |> assert_has(test_id("family-name"), text: "Big Family")
  end
end
```

- [ ] **Step 2: Run the E2E test**

Run: `mix test test/user_flows/create_subfamily_test.exs -v`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/create_subfamily_test.exs
git commit -m "Add E2E user flow test for create subfamily feature"
```

---

## Task 6: Final Verification

- [ ] **Step 1: Run precommit checks**

Run: `mix precommit`
Expected: All checks pass (compilation, formatting, tests)

- [ ] **Step 2: Fix any issues**

If any precommit checks fail, fix the issues and re-run.

- [ ] **Step 3: Final commit if needed**

If any fixes were required, commit them.

```bash
git add -A
git commit -m "Fix precommit issues for create subfamily feature"
```
