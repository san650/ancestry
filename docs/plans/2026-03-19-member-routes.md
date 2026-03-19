# Move Member Pages Outside Family Scope — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move person show pages from `/families/:family_id/members/:id` to `/people/:id` with optional `?from_family=` query param for back navigation context and TreeView loading.

**Architecture:** Add a top-level `/people/:id` route, update `PersonLive.Show` to read `from_family` from query params instead of path params, update all navigation links across components and templates to use the new URL pattern, and update all tests.

**Tech Stack:** Phoenix LiveView routes, verified routes (`~p`), query params via `handle_params`

---

### Task 1: Update router and PersonLive.Show mount

**Files:**
- Modify: `lib/web/router.ex:27`
- Modify: `lib/web/live/person_live/show.ex:9-33`

**Step 1: Update the router**

In `lib/web/router.ex`, replace line 27:
```elixir
# Remove:
live "/families/:family_id/members/:id", PersonLive.Show, :show
# Add:
live "/people/:id", PersonLive.Show, :show
```

**Step 2: Update PersonLive.Show mount and handle_params**

In `lib/web/live/person_live/show.ex`, replace `mount/3` and `handle_params/3`:

```elixir
@impl true
def mount(%{"id" => id}, _session, socket) do
  person = People.get_person!(id)

  if connected?(socket) do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "person:#{person.id}")
  end

  {:ok,
   socket
   |> assign(:person, person)
   |> assign(:from_family, nil)
   |> assign(:editing, false)
   |> assign(:confirm_remove, false)
   |> assign(:confirm_delete, false)
   |> load_relationships(person)
   |> allow_upload(:photo,
     accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
     max_entries: 1,
     max_file_size: 20 * 1_048_576
   )}
end

@impl true
def handle_params(params, _url, socket) do
  from_family =
    case params do
      %{"from_family" => family_id} -> Families.get_family!(family_id)
      _ -> nil
    end

  {:noreply, assign(socket, :from_family, from_family)}
end
```

**Step 3: Update confirm_remove and confirm_delete handlers**

Replace `handle_event("confirm_remove", ...)` — it still needs `@from_family`:

```elixir
def handle_event("confirm_remove", _, socket) do
  person = socket.assigns.person
  family = socket.assigns.from_family
  {:ok, _} = People.remove_from_family(person, family)
  {:noreply, push_navigate(socket, to: ~p"/families/#{family.id}")}
end
```

Replace `handle_event("confirm_delete", ...)`:

```elixir
def handle_event("confirm_delete", _, socket) do
  {:ok, _} = People.delete_person(socket.assigns.person)

  redirect_to =
    if socket.assigns.from_family do
      ~p"/families/#{socket.assigns.from_family.id}"
    else
      ~p"/"
    end

  {:noreply, push_navigate(socket, to: redirect_to)}
end
```

**Step 4: Run tests to see what breaks**

Run: `mix test --seed 0`
Expected: Many test failures due to old route pattern — this is expected, we'll fix in Task 4.

**Step 5: Commit**

```bash
git add lib/web/router.ex lib/web/live/person_live/show.ex
git commit -m "feat: move PersonLive.Show to /people/:id with from_family query param"
```

---

### Task 2: Update PersonLive.Show template

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Update back button**

Replace lines 5-10 in `show.html.heex`:

```heex
<%= if @from_family do %>
  <.link
    navigate={~p"/families/#{@from_family.id}?person=#{@person.id}"}
    class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
  >
    <.icon name="hero-arrow-left" class="w-5 h-5" />
  </.link>
<% else %>
  <.link
    navigate={~p"/"}
    class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
  >
    <.icon name="hero-arrow-left" class="w-5 h-5" />
  </.link>
<% end %>
```

**Step 2: Update "Remove from family" button visibility**

The "Remove" button only makes sense when `@from_family` is set. Wrap it:

```heex
<%= if @from_family do %>
  <button
    id="remove-from-family-btn"
    phx-click="request_remove"
    class="btn btn-ghost btn-sm text-error"
  >
    <.icon name="hero-user-minus" class="w-4 h-4" /> Remove
  </button>
<% end %>
```

**Step 3: Update all relationship person links**

Replace every occurrence of `~p"/families/#{@family.id}/members/#{...}"` with `~p"/people/#{...}"` plus the `from_family` param.

There are many occurrences. For each one, the pattern is:

```heex
# Old:
navigate={~p"/families/#{@family.id}/members/#{partner.id}"}
# New:
navigate={if @from_family, do: ~p"/people/#{partner.id}?from_family=#{@from_family.id}", else: ~p"/people/#{partner.id}"}
```

The occurrences are at these approximate lines (search for `families/#{@family.id}/members`):
- Line 198: partner link
- Line 274: child link (partner children)
- Line 305: coparent link
- Line 313: coparent children link
- Line 334: solo children link
- Line 375: parent link
- Line 446: sibling link

To keep the template DRY, add a helper function in `show.ex`:

```elixir
defp person_path(person, from_family) do
  if from_family do
    ~p"/people/#{person.id}?from_family=#{from_family.id}"
  else
    ~p"/people/#{person.id}"
  end
end
```

Then in the template, replace all navigation links:
```heex
navigate={person_path(partner, @from_family)}
```

**Step 4: Update the Remove modal text**

Replace `@family.name` with `@from_family.name` in the remove confirmation modal (around line 473):
```heex
from <span class="font-semibold">{@from_family.name}</span>?
```

**Step 5: Update AddRelationshipComponent invocation**

Replace `family={@family}` with `family={@from_family}` in the add-relationship modal (around line 525). The component will handle `nil` family (global search mode — see Task 3b):
```heex
family={@from_family}
```

Keep the modal condition as `<%= if @adding_relationship do %>` (no family requirement — component handles nil).

**Step 6: Update PersonFormComponent invocation**

The `person_form_component` call passes `family={@family}` — check if it uses family. If the component doesn't reference family (confirmed earlier), simply remove the `family` attr or change to `family={@from_family}`.

**Step 7: Commit**

```bash
git add lib/web/live/person_live/show.html.heex lib/web/live/person_live/show.ex
git commit -m "feat: update PersonLive.Show template for new route pattern"
```

---

### Task 3: Update navigation links in family components

**Files:**
- Modify: `lib/web/live/family_live/person_card_component.ex:27`
- Modify: `lib/web/live/family_live/people_list_component.ex:88`
- Modify: `lib/web/live/person_live/index.html.heex:47`

**Step 1: Update PersonCardComponent**

In `lib/web/live/family_live/person_card_component.ex`, line 27:

```elixir
# Old:
navigate={~p"/families/#{@family_id}/members/#{@person.id}"}
# New:
navigate={~p"/people/#{@person.id}?from_family=#{@family_id}"}
```

**Step 2: Update PeopleListComponent**

In `lib/web/live/family_live/people_list_component.ex`, line 88:

```elixir
# Old:
navigate={~p"/families/#{@family_id}/members/#{person.id}"}
# New:
navigate={~p"/people/#{person.id}?from_family=#{@family_id}"}
```

**Step 3: Update PersonLive.Index template**

In `lib/web/live/person_live/index.html.heex`, line 47:

```elixir
# Old:
navigate={~p"/families/#{@family.id}/members/#{person.id}"}
# New:
navigate={~p"/people/#{person.id}?from_family=#{@family.id}"}
```

**Step 4: Run tests to check progress**

Run: `mix test --seed 0`

**Step 5: Commit**

```bash
git add lib/web/live/family_live/person_card_component.ex lib/web/live/family_live/people_list_component.ex lib/web/live/person_live/index.html.heex
git commit -m "feat: update navigation links to use /people/:id?from_family= pattern"
```

---

### Task 3b: Make AddRelationshipComponent work without a family

**Files:**
- Modify: `lib/ancestry/people.ex` (add `search_all_people/2`, `create_person_without_family/1`)
- Modify: `lib/web/live/shared/add_relationship_component.ex`

The `AddRelationshipComponent` currently requires a `family` to search within. When used from PersonLive.Show without a family context, it should search ALL people in the system. Use separate functions — no nil-branching.

**Step 1: Add `search_all_people/2` to People context**

In `lib/ancestry/people.ex`, add a new function that searches all people excluding a specific person:

```elixir
def search_all_people(query, exclude_person_id) do
  escaped =
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")

  like = "%#{escaped}%"

  Repo.all(
    from p in Person,
      where: p.id != ^exclude_person_id,
      where:
        ilike(p.given_name, ^like) or
          ilike(p.surname, ^like) or
          ilike(p.nickname, ^like) or
          fragment(
            "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE name ILIKE ?)",
            p.alternate_names,
            ^like
          ),
      order_by: [asc: p.surname, asc: p.given_name],
      limit: 20,
      preload: [:families]
  )
end
```

**Step 2: Add `create_person_without_family/1` to People context**

```elixir
def create_person_without_family(attrs) do
  %Person{}
  |> Person.changeset(attrs)
  |> Repo.insert()
end
```

**Step 3: Split AddRelationshipComponent into two search/create strategies**

In `lib/web/live/shared/add_relationship_component.ex`:

Replace `handle_event("search_members", ...)` with two function clauses that use pattern matching on assigns:

```elixir
def handle_event("search_members", %{"value" => query}, %{assigns: %{family: %{} = family}} = socket) do
  results =
    if String.length(query) >= 2 do
      People.search_family_members(query, family.id, socket.assigns.person.id)
    else
      []
    end

  {:noreply,
   socket
   |> assign(:search_query, query)
   |> assign(:search_results, results)}
end

def handle_event("search_members", %{"value" => query}, socket) do
  results =
    if String.length(query) >= 2 do
      People.search_all_people(query, socket.assigns.person.id)
    else
      []
    end

  {:noreply,
   socket
   |> assign(:search_query, query)
   |> assign(:search_results, results)}
end
```

Replace `handle_event("save_person", ...)` with two clauses for the create path. Extract the person creation into a helper with two clauses:

```elixir
defp create_quick_person(%{family: %{} = family}, params) do
  People.create_person(family, params)
end

defp create_quick_person(_assigns, params) do
  People.create_person_without_family(params)
end
```

Then in `handle_event("save_person", ...)`, replace `People.create_person(socket.assigns.family, params)` with:

```elixir
case create_quick_person(socket.assigns, params) do
```

Also update the search step text (line 190):
```heex
Search for a person to add as a relationship.
```

**Step 4: Run tests**

Run: `mix test --seed 0`

**Step 5: Commit**

```bash
git add lib/ancestry/people.ex lib/web/live/shared/add_relationship_component.ex
git commit -m "feat: allow AddRelationshipComponent to work without family context"
```

---

### Task 4: Update tests

**Files:**
- Modify: `test/web/live/person_live/show_test.exs`
- Modify: `test/web/live/person_live/relationships_test.exs`
- Modify: `test/web/live/person_live/quick_create_test.exs`

**Step 1: Update all test routes**

In all three test files, replace every occurrence of:

```elixir
~p"/families/#{family.id}/members/#{person.id}"
```

with:

```elixir
~p"/people/#{person.id}?from_family=#{family.id}"
```

Use find-and-replace across the files. The pattern is consistent.

**Step 2: Run tests**

Run: `mix test test/web/live/person_live/ --seed 0`
Expected: All person live tests pass.

**Step 3: Run full test suite**

Run: `mix test --seed 0`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add test/web/live/person_live/
git commit -m "test: update person live tests for new /people/:id route"
```

---

### Task 5: Run precommit and verify

**Files:** None (verification only)

**Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass — no warnings, formatted, all tests pass.

**Step 2: Manual verification checklist**

Verify these navigation flows work correctly:
- From FamilyLive.Show, click person card arrow → goes to `/people/:id?from_family=:fid`
- On PersonLive.Show, click back arrow → goes to `/families/:fid?person=:id` (loads person in TreeView)
- On PersonLive.Show, click a related person → goes to `/people/:related_id?from_family=:fid`
- On PersonLive.Show, click "Remove from family" → removes and redirects to `/families/:fid`
- On PersonLive.Show, click "Delete" → deletes and redirects to `/families/:fid`
- From PeopleListComponent sidebar, click details icon → goes to `/people/:id?from_family=:fid`
- `/families/:family_id/members/new` still works (unchanged)

**Step 3: Commit if any formatting changes**

```bash
git add -A && git commit -m "chore: formatting fixes"
```
