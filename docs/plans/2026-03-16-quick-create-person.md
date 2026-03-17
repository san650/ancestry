# Quick Create Person Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Create new person" option inside the Add Relationship modal so users can create a person on-the-fly and immediately link them as parent, child, or spouse.

**Architecture:** A new `PersonLive.QuickCreateComponent` LiveComponent replaces the search view inside the existing modal. On successful creation, it messages the parent LiveView which feeds the new person into the existing metadata/save flow. Three touch points: the component (new file), the show LiveView (new assigns + events), and the show template (conditional rendering).

**Tech Stack:** Phoenix LiveView, LiveComponent, Ecto changesets

---

### Task 1: Create the QuickCreateComponent LiveComponent

**Files:**
- Create: `lib/web/live/person_live/quick_create_component.ex`

**Step 1: Write the failing test**

Create test file `test/web/live/person_live/quick_create_test.exs`:

```elixir
defmodule Web.PersonLive.QuickCreateTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.People

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})

    {:ok, person} =
      People.create_person(family, %{given_name: "John", surname: "Doe", gender: "male"})

    %{family: family, person: person}
  end

  test "shows create new person link in add relationship modal", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    assert has_element?(view, "#start-quick-create-btn")
  end

  test "switches to quick create form when clicking create new", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    assert has_element?(view, "#quick-create-person")
    assert has_element?(view, "#quick-create-person-form")
    refute has_element?(view, "#relationship-search-input")
  end

  test "back to search returns to search view", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()
    assert has_element?(view, "#quick-create-person-form")

    view |> element("#cancel-quick-create-btn") |> render_click()
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#relationship-search-input")
  end

  test "validates given_name is required", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    html =
      view
      |> form("#quick-create-person-form", person: %{given_name: "", surname: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "creates person and proceeds to parent metadata step", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewDad", surname: "Smith"})
    |> render_submit()

    # Should now be on the metadata step (parent role form)
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#add-parent-form")
  end

  test "creates person and proceeds to partner metadata step", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-partner-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewWife", surname: "Jones"})
    |> render_submit()

    # Should now be on the metadata step (partner marriage form)
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#add-partner-form")
  end

  test "creates person and saves child relationship directly", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-child-solo-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewKid", surname: "Doe"})
    |> render_submit()

    # For child, it goes to the child confirm step (select_person sets relationship_form to nil)
    assert has_element?(view, "#add-child-form")
  end

  test "new person is added to the family", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()

    view
    |> form("#quick-create-person-form", person: %{given_name: "NewMom", surname: "Lee"})
    |> render_submit()

    # Verify person was created in the family
    members = People.list_people_for_family(family.id)
    assert Enum.any?(members, &(&1.given_name == "NewMom" && &1.surname == "Lee"))
  end

  test "full flow: quick create parent then save relationship", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")

    # Open add parent modal
    view |> element("#add-parent-btn") |> render_click()

    # Switch to quick create
    view |> element("#start-quick-create-btn") |> render_click()

    # Create new person
    view
    |> form("#quick-create-person-form",
      person: %{given_name: "QuickDad", surname: "Fast"}
    )
    |> render_submit()

    # Now on metadata step — submit parent role form
    view |> form("#add-parent-form") |> render_submit()

    # Modal closed, relationship created
    refute has_element?(view, "#add-relationship-modal")
    assert render(view) =~ "QuickDad"
  end

  test "closing modal resets quick_creating state", %{
    conn: conn,
    family: family,
    person: person
  } do
    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")
    view |> element("#add-parent-btn") |> render_click()
    view |> element("#start-quick-create-btn") |> render_click()
    assert has_element?(view, "#quick-create-person-form")

    # Close modal
    view |> element("#add-parent-btn") |> render_click()

    # Reopen — should be back to search, not quick create
    refute has_element?(view, "#quick-create-person-form")
    assert has_element?(view, "#relationship-search-input")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/person_live/quick_create_test.exs`
Expected: FAIL — component doesn't exist, `start-quick-create-btn` not found

**Step 3: Write the QuickCreateComponent**

Create `lib/web/live/person_live/quick_create_component.ex`:

```elixir
defmodule Web.PersonLive.QuickCreateComponent do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:family, assigns.family)
     |> assign(:relationship_type, assigns.relationship_type)
     |> assign_new(:form, fn -> to_form(People.change_person(%Person{}), as: :person) end)}
  end

  @impl true
  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
  end

  def handle_event("save", %{"person" => params}, socket) do
    case People.create_person(socket.assigns.family, params) do
      {:ok, person} ->
        person = People.get_person!(person.id)
        send(self(), {:person_created, person, socket.assigns.relationship_type})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="quick-create-person">
      <button
        id="cancel-quick-create-btn"
        phx-click="cancel_quick_create"
        class="flex items-center gap-1 text-sm text-primary/70 hover:text-primary mb-4 transition-colors"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to search
      </button>

      <p class="text-sm text-base-content/60 mb-4">
        Create a new person to add as a relationship.
      </p>

      <.form
        for={@form}
        id="quick-create-person-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <.input field={@form[:given_name]} label="Given name" />
          <.input field={@form[:surname]} label="Surname" />
          <button type="submit" class="btn btn-primary w-full">
            Create & Continue
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
```

**Step 4: Run test to verify it still fails (component exists but not wired up yet)**

Run: `mix test test/web/live/person_live/quick_create_test.exs`
Expected: FAIL — `start-quick-create-btn` not found in template yet

**Step 5: Commit**

```bash
git add lib/web/live/person_live/quick_create_component.ex test/web/live/person_live/quick_create_test.exs
git commit -m "Add QuickCreateComponent and tests (not wired up yet)"
```

---

### Task 2: Wire up PersonLive.Show — new assigns and event handlers

**Files:**
- Modify: `lib/web/live/person_live/show.ex`

**Step 1: Add `quick_creating` assign to `load_relationships/2`**

In `lib/web/live/person_live/show.ex:452` (end of `load_relationships`), add the new assign. The assign is reset here so closing the modal or saving a relationship also resets it.

Add `|> assign(:quick_creating, false)` at the end of the assign pipeline in `load_relationships/2`, after line 451 (`|> assign(:adding_partner_id, nil)`).

**Step 2: Add `handle_event` for `"start_quick_create"` and `"cancel_quick_create"`**

Insert after the `cancel_add_relationship` handler (after line 139):

```elixir
def handle_event("start_quick_create", _, socket) do
  {:noreply, assign(socket, :quick_creating, true)}
end

def handle_event("cancel_quick_create", _, socket) do
  {:noreply, assign(socket, :quick_creating, false)}
end
```

**Step 3: Add `handle_info` for `{:person_created, person, type}`**

Insert after the existing `handle_info` handlers (after line 376):

```elixir
def handle_info({:person_created, person, type}, socket) do
  relationship_form =
    case type do
      "parent" ->
        role = if person.gender == "male", do: "father", else: "mother"
        to_form(%{"role" => role}, as: :metadata)

      "partner" ->
        to_form(%{}, as: :metadata)

      _ ->
        nil
    end

  {:noreply,
   socket
   |> assign(:quick_creating, false)
   |> assign(:selected_person, person)
   |> assign(:relationship_form, relationship_form)}
end
```

**Step 4: Also reset `quick_creating` in `cancel_add_relationship`**

Add `|> assign(:quick_creating, false)` to the `cancel_add_relationship` handler pipeline (line 130-138).

**Step 5: Also reset `quick_creating` in `add_relationship` and `add_child_for_partner`**

Add `|> assign(:quick_creating, false)` to both the `add_relationship` handler (line 108-117) and the `add_child_for_partner` handler (line 119-128).

**Step 6: Run test to verify still failing (template not updated yet)**

Run: `mix test test/web/live/person_live/quick_create_test.exs`
Expected: FAIL — `start-quick-create-btn` still not in template

**Step 7: Commit**

```bash
git add lib/web/live/person_live/show.ex
git commit -m "Add quick_creating assigns and event handlers to PersonLive.Show"
```

---

### Task 3: Update the show template to render QuickCreateComponent

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Add conditional rendering in the Add Relationship modal**

In `show.html.heex`, the Add Relationship modal starts at line 636. Inside it, the search view is at line 659 (`<%= if @selected_person == nil do %>`). We need to wrap the search section with a quick_creating check.

Replace the block starting at line 659 (`<%= if @selected_person == nil do %>`) through the end of the search section (before `<% else %>` at line 697) with:

```heex
<%= if @selected_person == nil do %>
  <%= if @quick_creating do %>
    <.live_component
      module={Web.PersonLive.QuickCreateComponent}
      id="quick-create-person"
      family={@family}
      relationship_type={@adding_relationship}
    />
  <% else %>
    <%!-- Step 1: Search for a person --%>
    <div class="space-y-4">
      <p class="text-sm text-base-content/60">
        Search for an existing family member to add as a relationship.
      </p>
      <input
        id="relationship-search-input"
        type="text"
        placeholder="Type a name to search..."
        value={@search_query}
        phx-keyup="search_members"
        phx-debounce="300"
        class="input input-bordered w-full"
        autocomplete="off"
      />

      <%= if @search_results != [] do %>
        <div class="space-y-1 max-h-60 overflow-y-auto">
          <%= for result <- @search_results do %>
            <button
              id={"search-result-#{result.id}"}
              phx-click="select_person"
              phx-value-id={result.id}
              class="w-full text-left rounded-lg transition-colors hover:bg-base-200"
            >
              <.person_card person={result} highlighted={false} />
            </button>
          <% end %>
        </div>
      <% else %>
        <%= if String.length(@search_query) >= 2 do %>
          <p class="text-sm text-base-content/40 text-center py-4">
            No results found
          </p>
        <% end %>
      <% end %>

      <%!-- Quick create link --%>
      <button
        id="start-quick-create-btn"
        phx-click="start_quick_create"
        class="flex items-center gap-1.5 text-sm text-primary/70 hover:text-primary w-full justify-center py-2 border-t border-base-200 mt-2 transition-colors"
      >
        <.icon name="hero-plus" class="w-4 h-4" /> Person not listed? Create new
      </button>
    </div>
  <% end %>
```

**Step 2: Add the `validate_required` for given_name in the component's save handler**

The `Person.changeset/2` doesn't require `given_name`. We need to add validation in the component. Update the `save` handler in `quick_create_component.ex` to validate before creating:

```elixir
def handle_event("save", %{"person" => params}, socket) do
  changeset =
    %Person{}
    |> People.change_person(params)
    |> Ecto.Changeset.validate_required([:given_name])

  if changeset.valid? do
    case People.create_person(socket.assigns.family, params) do
      {:ok, person} ->
        person = People.get_person!(person.id)
        send(self(), {:person_created, person, socket.assigns.relationship_type})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
    end
  else
    {:noreply,
     assign(socket, :form, to_form(%{changeset | action: :validate}, as: :person))}
  end
end
```

**Step 3: Run all quick create tests**

Run: `mix test test/web/live/person_live/quick_create_test.exs`
Expected: ALL PASS

**Step 4: Run existing relationship tests to verify no regressions**

Run: `mix test test/web/live/person_live/relationships_test.exs`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add lib/web/live/person_live/show.html.heex lib/web/live/person_live/quick_create_component.ex
git commit -m "Wire up QuickCreateComponent in add relationship modal template"
```

---

### Task 4: Run full test suite and precommit

**Step 1: Run all tests**

Run: `mix test`
Expected: ALL PASS

**Step 2: Run precommit**

Run: `mix precommit`
Expected: ALL PASS (compile warnings-as-errors, format, tests)

**Step 3: Fix any issues found by precommit**

If format or warnings issues, fix and commit.

**Step 4: Final commit if needed**

```bash
git add -A
git commit -m "Fix formatting/warnings from precommit"
```
