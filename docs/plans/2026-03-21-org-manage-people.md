# Org-Level Manage People Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a "Manage People" page at `/org/:org_id/people` showing all people in the organization with search, "No family" filter, and bulk permanent delete.

**Architecture:** New `OrgPeopleLive.Index` LiveView mirrors the family-level `PeopleLive.Index` but queries org-scoped people, uses permanent delete instead of detach, and filters by "No family" instead of "Unlinked." Context functions added to `People` module. `PersonLive.Show` updated for back-navigation from org context.

**Tech Stack:** Phoenix LiveView, Ecto, ExMachina (tests), PhoenixTest.Playwright (E2E tests)

**Spec:** `docs/superpowers/specs/2026-03-21-org-manage-people-design.md`

---

## File Structure

### Create
- `lib/web/live/org_people_live/index.ex` — LiveView module with mount, events, helpers
- `lib/web/live/org_people_live/index.html.heex` — Template with table, search, filters, modals
- `test/user_flows/org_manage_people_test.exs` — E2E tests

### Modify
- `lib/ancestry/people.ex` — Add `list_people_for_org/1,2,3`, `delete_people/1`, `base_org_people_query/1`
- `lib/web/router.ex` — Add route
- `lib/web/live/family_live/index.html.heex` — Add "People" button to toolbar
- `lib/web/live/person_live/show.ex` — Handle `from_org` param, update `confirm_delete`
- `lib/web/live/person_live/show.html.heex` — Back nav for org context

---

### Task 1: Context Layer — `People.list_people_for_org/1,2,3`

**Files:**
- Modify: `lib/ancestry/people.ex`
- Modify: `test/ancestry/people_test.exs` (existing file — add to it)

- [ ] **Step 1: Write tests for `list_people_for_org`**

The file `test/ancestry/people_test.exs` already exists with many test blocks. Add `alias Ancestry.Relationships` after the existing `alias Ancestry.People.Person` on line 7. Then add the following `describe` block **before the closing `end` of the module** (line 489):

```elixir
  describe "list_people_for_org/1,2,3" do
    setup do
      org = insert(:organization, name: "Test Org")
      family = insert(:family, name: "Fam A", organization: org)

      alice = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
      bob = insert(:person, given_name: "Bob", surname: "Jones", organization: org)
      orphan = insert(:person, given_name: "Orphan", surname: "Nobody", organization: org)

      # Different org — should never appear
      other_org = insert(:organization, name: "Other")
      _outsider = insert(:person, given_name: "Outside", surname: "Person", organization: other_org)

      People.add_to_family(alice, family)
      People.add_to_family(bob, family)
      # orphan has no family

      Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})

      %{org: org, family: family, alice: alice, bob: bob, orphan: orphan}
    end

    test "returns all people in the org with relationship counts", %{
      org: org,
      alice: alice,
      bob: bob,
      orphan: orphan
    } do
      results = People.list_people_for_org(org.id)
      people_map = Map.new(results, fn {p, count} -> {p.id, count} end)

      assert map_size(people_map) == 3
      assert people_map[alice.id] == 1
      assert people_map[bob.id] == 1
      assert people_map[orphan.id] == 0
    end

    test "filters by search term with diacritics", %{org: org} do
      results = People.list_people_for_org(org.id, "alice")
      assert length(results) == 1
      assert elem(hd(results), 0).given_name == "Alice"
    end

    test "returns empty for no match", %{org: org} do
      assert People.list_people_for_org(org.id, "zzzzz") == []
    end

    test "no_family_only filters to people without families", %{org: org, orphan: orphan} do
      results = People.list_people_for_org(org.id, no_family_only: true)
      assert length(results) == 1
      assert elem(hd(results), 0).id == orphan.id
    end

    test "no_family_only with search", %{org: org} do
      results = People.list_people_for_org(org.id, "Orphan", no_family_only: true)
      assert length(results) == 1

      results = People.list_people_for_org(org.id, "Alice", no_family_only: true)
      assert results == []
    end

    test "does not include people from other orgs", %{org: org} do
      results = People.list_people_for_org(org.id)
      given_names = Enum.map(results, fn {p, _} -> p.given_name end)
      refute "Outside" in given_names
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs -v`
Expected: FAIL — `list_people_for_org` is undefined

- [ ] **Step 3: Implement `list_people_for_org` and `base_org_people_query`**

Add to `lib/ancestry/people.ex` (after the existing `list_people_for_family_with_relationship_counts` functions):

```elixir
  def list_people_for_org(org_id) do
    base_org_people_query(org_id)
    |> Repo.all()
  end

  def list_people_for_org(org_id, opts) when is_list(opts) do
    no_family_only = Keyword.get(opts, :no_family_only, false)

    base_org_people_query(org_id)
    |> maybe_filter_no_family(no_family_only)
    |> Repo.all()
  end

  def list_people_for_org(org_id, search_term) when is_binary(search_term) do
    list_people_for_org(org_id, search_term, [])
  end

  def list_people_for_org(org_id, "", opts), do: list_people_for_org(org_id, opts)

  def list_people_for_org(org_id, search_term, opts) do
    no_family_only = Keyword.get(opts, :no_family_only, false)

    escaped =
      search_term
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"

    base_org_people_query(org_id)
    |> where(
      [p],
      fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
        fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
        fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like)
    )
    |> maybe_filter_no_family(no_family_only)
    |> Repo.all()
  end

  defp base_org_people_query(org_id) do
    from p in Person,
      where: p.organization_id == ^org_id,
      left_join: r in Relationship,
      on: r.person_a_id == p.id or r.person_b_id == p.id,
      group_by: p.id,
      order_by: [asc: p.surname, asc: p.given_name],
      select: {p, count(r.id, :distinct)}
  end

  defp maybe_filter_no_family(query, true) do
    query
    |> join(:left, [p], fm in FamilyMember, on: fm.person_id == p.id, as: :fm_no_family)
    |> having([fm_no_family: fm], fragment("COUNT(DISTINCT ?) = 0", fm.family_id))
  end

  defp maybe_filter_no_family(query, false), do: query
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/people_test.exs -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Add People.list_people_for_org/1,2,3 with search and no-family filter"
```

---

### Task 2: Context Layer — `People.delete_people/1`

**Files:**
- Modify: `lib/ancestry/people.ex`
- Test: `test/ancestry/people_test.exs`

- [ ] **Step 1: Write test for `delete_people/1`**

Add the following `describe` block to `test/ancestry/people_test.exs`, after the `list_people_for_org` block added in Task 1:

```elixir
  describe "delete_people/1" do
    test "deletes multiple people and cleans up files" do
      org = insert(:organization)
      p1 = insert(:person, given_name: "Del1", organization: org)
      p2 = insert(:person, given_name: "Del2", organization: org)
      p3 = insert(:person, given_name: "Keep", organization: org)

      assert {:ok, _} = People.delete_people([p1.id, p2.id])

      assert_raise Ecto.NoResultsError, fn -> People.get_person!(p1.id) end
      assert_raise Ecto.NoResultsError, fn -> People.get_person!(p2.id) end
      assert People.get_person!(p3.id)
    end

    test "returns ok for empty list" do
      assert {:ok, _} = People.delete_people([])
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs --only describe:"delete_people/1" -v`
Expected: FAIL — `delete_people` is undefined

- [ ] **Step 3: Implement `delete_people/1`**

Add to `lib/ancestry/people.ex`:

```elixir
  def delete_people(person_ids) do
    Repo.transaction(fn ->
      for id <- person_ids do
        person = get_person!(id)
        {:ok, _} = delete_person(person)
      end
    end)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/people_test.exs -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Add People.delete_people/1 for bulk permanent delete"
```

---

### Task 3: Route & FamilyLive.Index Toolbar

**Files:**
- Modify: `lib/web/router.ex:29-40` — add route inside `:organization` live_session
- Modify: `lib/web/live/family_live/index.html.heex:2-14` — add "People" button to toolbar

- [ ] **Step 1: Add route**

In `lib/web/router.ex`, inside the `scope "/org/:org_id" do` / `live_session :organization` block, add after the existing `live "/families/:family_id/people", PeopleLive.Index, :index` line:

```elixir
        live "/people", OrgPeopleLive.Index, :index
```

- [ ] **Step 2: Add "People" button to FamilyLive.Index toolbar**

In `lib/web/live/family_live/index.html.heex`, replace the toolbar section (lines 2-14):

```heex
  <:toolbar>
    <div class="max-w-7xl mx-auto flex items-center justify-between py-3">
      <h1 class="text-3xl font-bold tracking-tight text-base-content">Families</h1>
      <div class="flex items-center gap-2">
        <.link
          navigate={~p"/org/#{@organization.id}/people"}
          class="btn btn-ghost"
          {test_id("org-people-btn")}
        >
          <.icon name="hero-users" class="w-4 h-4" /> People
        </.link>
        <.link
          id="new-family-btn"
          navigate={~p"/org/#{@organization.id}/families/new"}
          class="btn btn-primary"
          {test_id("family-new-btn")}
        >
          New Family
        </.link>
      </div>
    </div>
  </:toolbar>
```

- [ ] **Step 3: Create empty LiveView to avoid compilation error**

Create `lib/web/live/org_people_live/index.ex` with a minimal stub:

```elixir
defmodule Web.OrgPeopleLive.Index do
  use Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} organization={@organization}>
      <p>Org people — coming soon</p>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles without errors

- [ ] **Step 5: Commit**

```bash
git add lib/web/router.ex lib/web/live/family_live/index.html.heex lib/web/live/org_people_live/index.ex
git commit -m "Add org people route and People toolbar button on family index"
```

---

### Task 4: OrgPeopleLive.Index — LiveView Module

**Files:**
- Modify: `lib/web/live/org_people_live/index.ex` — full implementation

- [ ] **Step 1: Implement the full LiveView module**

Replace `lib/web/live/org_people_live/index.ex` with:

```elixir
defmodule Web.OrgPeopleLive.Index do
  use Web, :live_view

  alias Ancestry.People

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.organization
    people = People.list_people_for_org(org.id)

    {:ok,
     socket
     |> assign(:filter, "")
     |> assign(:editing, false)
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_delete, false)
     |> assign(:no_family_only, false)
     |> assign(:people_empty?, people == [])
     |> stream_configure(:people, dom_id: fn {person, _rel_count} -> "people-#{person.id}" end)
     |> stream(:people, people)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", %{"filter" => query}, socket) do
    org_id = socket.assigns.organization.id
    people = People.list_people_for_org(org_id, query, no_family_only: socket.assigns.no_family_only)

    {:noreply,
     socket
     |> assign(:filter, query)
     |> assign(:selected, MapSet.new())
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_edit", _, socket) do
    editing = !socket.assigns.editing
    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:editing, editing)
     |> assign(:selected, MapSet.new())
     |> stream(:people, people, reset: true)}
  end

  def handle_event("toggle_no_family", _, socket) do
    no_family_only = !socket.assigns.no_family_only
    people = refetch_people(socket, no_family_only: no_family_only)

    {:noreply,
     socket
     |> assign(:no_family_only, no_family_only)
     |> assign(:selected, MapSet.new())
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)}
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

    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, selected)
     |> stream(:people, people, reset: true)}
  end

  def handle_event("select_all", _, socket) do
    people = refetch_people(socket)
    ids = MapSet.new(people, fn {p, _} -> p.id end)

    {:noreply,
     socket
     |> assign(:selected, ids)
     |> stream(:people, people, reset: true)}
  end

  def handle_event("deselect_all", _, socket) do
    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> stream(:people, people, reset: true)}
  end

  def handle_event("request_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("request_delete_one", %{"id" => id}, socket) do
    if socket.assigns.confirm_delete do
      {:noreply, socket}
    else
      person_id = String.to_integer(id)

      {:noreply,
       socket
       |> assign(:selected, MapSet.new([person_id]))
       |> assign(:confirm_delete, true)}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, false)}
  end

  def handle_event("confirm_delete", _, socket) do
    selected = socket.assigns.selected
    count = MapSet.size(selected)

    People.delete_people(MapSet.to_list(selected))

    people = refetch_people(socket)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> assign(:confirm_delete, false)
     |> assign(:people_empty?, people == [])
     |> stream(:people, people, reset: true)
     |> put_flash(
       :info,
       "Deleted #{count} #{if count == 1, do: "person", else: "people"}."
     )}
  end

  defp refetch_people(socket, opts \\ []) do
    no_family_only = Keyword.get(opts, :no_family_only, socket.assigns.no_family_only)

    People.list_people_for_org(
      socket.assigns.organization.id,
      socket.assigns.filter,
      no_family_only: no_family_only
    )
  end

  def estimated_age(%{birth_year: nil}), do: nil

  def estimated_age(%{deceased: true, death_year: nil}), do: nil

  def estimated_age(%{deceased: true, birth_year: birth_year, death_year: death_year}),
    do: death_year - birth_year

  def estimated_age(%{birth_year: birth_year}),
    do: Date.utc_today().year - birth_year
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles (template will be added in next task)

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/org_people_live/index.ex
git commit -m "Implement OrgPeopleLive.Index LiveView module"
```

---

### Task 5: OrgPeopleLive.Index — Template

**Files:**
- Create: `lib/web/live/org_people_live/index.html.heex`

- [ ] **Step 1: Create the template**

Create `lib/web/live/org_people_live/index.html.heex`:

```heex
<Layouts.app flash={@flash} organization={@organization}>
  <:toolbar>
    <div class="max-w-full mx-auto flex items-center justify-between py-3 px-4">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/org/#{@organization.id}"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
          {test_id("org-people-back-btn")}
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content truncate">
          People
        </h1>
      </div>
      <div class="flex items-center gap-2">
        <%= if @editing && MapSet.size(@selected) > 0 do %>
          <button
            phx-click="request_delete"
            class="btn btn-error btn-sm"
            {test_id("org-people-delete-btn")}
          >
            <.icon name="hero-trash" class="w-4 h-4" /> Delete
          </button>
        <% end %>
        <button
          phx-click="toggle_edit"
          class={[
            "btn btn-sm",
            if(@editing, do: "btn-primary", else: "btn-ghost")
          ]}
          {test_id("org-people-edit-btn")}
        >
          <%= if @editing do %>
            Done
          <% else %>
            <.icon name="hero-pencil" class="w-4 h-4" /> Edit
          <% end %>
        </button>
      </div>
    </div>
  </:toolbar>

  <%!-- Search box + No family chip --%>
  <div class="px-4 pt-4 pb-2 max-w-4xl mx-auto w-full">
    <div class="flex items-center gap-2">
      <div class="relative flex-1" {test_id("org-people-search")}>
        <form phx-change="filter" phx-submit="filter">
          <.icon
            name="hero-magnifying-glass"
            class="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none"
          />
          <input
            type="text"
            name="filter"
            value={@filter}
            phx-debounce="300"
            placeholder="Search people..."
            class="input input-bordered w-full pl-10"
          />
        </form>
      </div>
      <button
        phx-click="toggle_no_family"
        class={[
          "btn btn-sm gap-1",
          if(@no_family_only, do: "btn-warning", else: "btn-ghost")
        ]}
        {test_id("org-people-no-family-chip")}
      >
        <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4" /> No family
      </button>
    </div>
  </div>

  <%!-- Select all / deselect all bar --%>
  <%= if @editing do %>
    <div class="px-4 pb-2 max-w-4xl mx-auto w-full">
      <div class="flex items-center gap-3 text-sm text-base-content/60">
        <button phx-click="select_all" class="link link-hover link-primary">Select all</button>
        <span class="text-base-content/20">|</span>
        <button phx-click="deselect_all" class="link link-hover link-primary">
          Deselect all
        </button>
        <%= if MapSet.size(@selected) > 0 do %>
          <span class="text-base-content/40 ml-auto">
            {MapSet.size(@selected)} selected
          </span>
        <% end %>
      </div>
    </div>
  <% end %>

  <%!-- Table --%>
  <div class={[
    "px-4 pb-8 max-w-4xl mx-auto w-full grid items-center",
    if(@editing,
      do: "grid-cols-[auto_auto_auto_auto_auto_auto_1fr]",
      else: "grid-cols-[auto_auto_auto_auto_auto_1fr]"
    )
  ]}>
    <%!-- Header cells --%>
    <div class="contents text-sm font-medium text-base-content/50">
      <%= if @editing do %>
        <div class="px-3 py-2.5 border-b border-base-200"></div>
      <% end %>
      <div class="px-3 py-2.5 border-b border-base-200"></div>
      <div class="px-3 py-2.5 border-b border-base-200">Name</div>
      <div class="px-3 py-2.5 border-b border-base-200">Est. Age</div>
      <div class="px-3 py-2.5 border-b border-base-200">Lifespan</div>
      <div class="px-3 py-2.5 border-b border-base-200">Links</div>
      <div class="px-3 py-2.5 border-b border-base-200"></div>
    </div>

    <%!-- Stream rows --%>
    <div
      id="org-people-table"
      phx-update="stream"
      class="contents"
      {test_id("org-people-table")}
    >
      <div id="org-people-empty-state" class="hidden only:block col-span-full py-16 text-center">
        <.icon name="hero-users" class="w-12 h-12 mx-auto mb-3 text-base-content/20" />
        <p class="text-lg font-medium text-base-content/40">No people in this organization</p>
      </div>

      <div
        :for={{dom_id, {person, rel_count}} <- @streams.people}
        id={dom_id}
        data-row
        class="contents"
        {test_id("org-people-row-#{person.id}")}
      >
        <%!-- Checkbox cell (edit mode only) --%>
        <%= if @editing do %>
          <div class="px-3 py-2.5">
            <button
              phx-click="toggle_select"
              phx-value-id={person.id}
              class={[
                "w-5 h-5 rounded border-2 flex items-center justify-center shrink-0 transition-colors",
                if(MapSet.member?(@selected, person.id),
                  do: "bg-primary border-primary text-primary-content",
                  else: "border-base-300 hover:border-primary"
                )
              ]}
              {test_id("org-people-checkbox-#{person.id}")}
            >
              <%= if MapSet.member?(@selected, person.id) do %>
                <.icon name="hero-check" class="w-3 h-3" />
              <% end %>
            </button>
          </div>
        <% end %>

        <%!-- Photo cell with alive/deceased indicator --%>
        <div class="px-3 py-2.5">
          <div class="indicator">
            <%= if person.deceased do %>
              <span
                class="indicator-item indicator-end badge badge-xs bg-transparent border-base-300"
                title="Deceased"
              >
                d.
              </span>
            <% end %>
            <div class="w-10 h-10 rounded-full overflow-hidden bg-base-200 flex items-center justify-center">
              <%= if person.photo && person.photo_status == "processed" do %>
                <img
                  src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                  alt={Ancestry.People.Person.display_name(person)}
                  class="w-full h-full object-cover"
                />
              <% else %>
                <.icon name="hero-user" class="w-5 h-5 text-base-content/30" />
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Name cell --%>
        <div class="px-3 py-2.5 min-w-0">
          <.link
            navigate={~p"/org/#{@organization.id}/people/#{person.id}?from_org=true"}
            class="font-medium text-base-content hover:text-primary truncate block"
          >
            <%= if person.surname && person.surname != "" do %>
              {person.surname}, {person.given_name}
            <% else %>
              {person.given_name}
            <% end %>
          </.link>
        </div>

        <%!-- Estimated Age cell --%>
        <div class="px-3 py-2.5 text-sm text-base-content/60">
          <%= case estimated_age(person) do %>
            <% nil -> %>
              &mdash;
            <% age -> %>
              ~{age}
          <% end %>
        </div>

        <%!-- Lifespan cell --%>
        <div class="px-3 py-2.5 text-sm text-base-content/60">
          <%= cond do %>
            <% person.birth_year && person.death_year -> %>
              b. {person.birth_year} &ndash; d. {person.death_year}
            <% person.birth_year -> %>
              b. {person.birth_year}
            <% person.death_year -> %>
              d. {person.death_year}
            <% true -> %>
              &mdash;
          <% end %>
        </div>

        <%!-- Links cell --%>
        <div class="px-3 py-2.5 text-sm" {test_id("org-people-links-#{person.id}")}>
          <%= if rel_count > 0 do %>
            <span class="text-base-content/60">{rel_count}</span>
          <% else %>
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-warning" />
          <% end %>
        </div>

        <%!-- Actions cell --%>
        <div class="px-3 py-2.5 flex items-center justify-end gap-1">
          <%= unless @editing do %>
            <.link
              navigate={~p"/org/#{@organization.id}/people/#{person.id}?from_org=true&edit=true"}
              class="btn btn-ghost btn-xs btn-circle text-base-content/40 hover:text-primary"
              title="Edit person"
              {test_id("org-people-edit-person-#{person.id}")}
            >
              <.icon name="hero-pencil-square" class="w-4 h-4" />
            </.link>
            <button
              phx-click="request_delete_one"
              phx-value-id={person.id}
              class="btn btn-ghost btn-xs btn-circle text-base-content/40 hover:text-error"
              title="Delete person"
              {test_id("org-people-delete-person-#{person.id}")}
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <%!-- Confirmation modal --%>
  <%= if @confirm_delete do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete"></div>
      <div
        id="confirm-delete-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
        {test_id("org-people-confirm-delete-modal")}
      >
        <h2 class="text-xl font-bold text-base-content mb-2">Delete People</h2>
        <p class="text-base-content/60 mb-6">
          Permanently delete <span class="font-semibold">{MapSet.size(@selected)}</span>
          {if MapSet.size(@selected) == 1, do: "person", else: "people"}? This cannot be undone. All their photos, relationships, and family links will be removed.
        </p>
        <div class="flex gap-3">
          <button
            phx-click="confirm_delete"
            class="btn btn-error flex-1"
            {test_id("org-people-confirm-delete-btn")}
          >
            Delete
          </button>
          <button
            phx-click="cancel_delete"
            class="btn btn-ghost flex-1"
            {test_id("org-people-cancel-delete-btn")}
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/org_people_live/index.html.heex
git commit -m "Add OrgPeopleLive.Index template with table, search, filters, modals"
```

---

### Task 6: PersonLive.Show — Back Navigation from Org

**Files:**
- Modify: `lib/web/live/person_live/show.ex:25-26,43-56,148-159`
- Modify: `lib/web/live/person_live/show.html.heex:1-21`

- [ ] **Step 1: Update `mount` to initialize `from_org`**

In `lib/web/live/person_live/show.ex`, add `from_org: false` to the mount assigns. Find:

```elixir
     |> assign(:from_family, nil)
```

Replace with:

```elixir
     |> assign(:from_family, nil)
     |> assign(:from_org, false)
```

- [ ] **Step 2: Update `handle_params` to handle `from_org`**

In `lib/web/live/person_live/show.ex`, replace the `handle_params` function:

```elixir
  @impl true
  def handle_params(params, _url, socket) do
    from_family =
      case params do
        %{"from_family" => family_id} -> Families.get_family!(family_id)
        _ -> nil
      end

    from_org = params["from_org"] == "true"

    socket =
      socket
      |> assign(:from_family, from_family)
      |> assign(:from_org, from_org)
      |> maybe_enter_edit_mode(params["edit"] == "true")

    {:noreply, socket}
  end
```

- [ ] **Step 3: Update `confirm_delete` handler to use `cond`**

In `lib/web/live/person_live/show.ex`, replace the `confirm_delete` handler:

```elixir
  def handle_event("confirm_delete", _, socket) do
    {:ok, _} = People.delete_person(socket.assigns.person)

    redirect_to =
      cond do
        socket.assigns.from_family ->
          ~p"/org/#{socket.assigns.organization.id}/families/#{socket.assigns.from_family.id}"

        socket.assigns.from_org ->
          ~p"/org/#{socket.assigns.organization.id}/people"

        true ->
          ~p"/org/#{socket.assigns.organization.id}"
      end

    {:noreply, push_navigate(socket, to: redirect_to)}
  end
```

- [ ] **Step 4: Update template back arrow**

In `lib/web/live/person_live/show.html.heex`, replace lines 5-21 (the back arrow `if/else`) with:

```heex
        <%= cond do %>
          <% @from_family -> %>
            <.link
              navigate={
                ~p"/org/#{@organization.id}/families/#{@from_family.id}?person=#{@person.id}"
              }
              class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
          <% @from_org -> %>
            <.link
              navigate={~p"/org/#{@organization.id}/people"}
              class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
          <% true -> %>
            <.link
              navigate={~p"/org/#{@organization.id}"}
              class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
        <% end %>
```

- [ ] **Step 5: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "Add from_org back navigation in PersonLive.Show"
```

---

### Task 7: E2E Tests

**Files:**
- Create: `test/user_flows/org_manage_people_test.exs`

- [ ] **Step 1: Write E2E tests**

Create `test/user_flows/org_manage_people_test.exs`:

```elixir
defmodule Web.UserFlows.OrgManagePeopleTest do
  use Web.E2ECase

  # Given an organization with families and people
  # When the user clicks "People" on the org landing page
  # Then the org people page is displayed with all people
  #
  # When the user types a search term
  # Then the table filters to matching people
  #
  # When the user clicks the "No family" chip
  # Then only people without family links are shown
  #
  # When the user clicks "Edit", selects people, and clicks "Delete"
  # Then a confirmation modal appears
  # When the user confirms
  # Then the selected people are permanently deleted
  #
  # When the user navigates to a person from the org people page
  # And clicks the back arrow
  # Then they return to the org people page

  setup do
    org = insert(:organization, name: "Test Org")
    family = insert(:family, name: "The Smiths", organization: org)

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Smith",
        birth_year: 1950,
        death_year: 2020,
        deceased: true,
        organization: org
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Smith",
        birth_year: 1955,
        organization: org
      )

    # Orphan — not in any family
    orphan =
      insert(:person,
        given_name: "Orphan",
        surname: "Nobody",
        organization: org
      )

    for p <- [alice, bob], do: Ancestry.People.add_to_family(p, family)

    # Alice parent of Bob — 1 relationship each
    Ancestry.Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})

    %{org: org, family: family, alice: alice, bob: bob, orphan: orphan}
  end

  test "navigate to org people page from family index", %{conn: conn, org: org} do
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click(test_id("org-people-btn"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("org-people-table"))
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice")
    |> assert_has(test_id("org-people-table"), text: "Smith, Bob")
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "search filters the table", %{conn: conn, org: org} do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    conn = PhoenixTest.Playwright.type(conn, test_id("org-people-search") <> " input", "Smith")

    conn
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice", timeout: 5_000)
    |> assert_has(test_id("org-people-table"), text: "Smith, Bob")
    |> refute_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "no family chip filters to people without families", %{conn: conn, org: org} do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()
      |> click(test_id("org-people-no-family-chip"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan", timeout: 5_000)
    |> refute_has(test_id("org-people-table"), text: "Smith, Alice")
    |> refute_has(test_id("org-people-table"), text: "Smith, Bob")

    # Toggle off — all visible again
    conn =
      conn
      |> click(test_id("org-people-no-family-chip"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice", timeout: 5_000)
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "bulk delete people", %{conn: conn, org: org, orphan: orphan, bob: bob} do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Enter edit mode
    conn =
      conn
      |> click(test_id("org-people-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-checkbox-#{orphan.id}"), timeout: 5_000)

    # Select orphan and bob
    conn =
      conn
      |> click(test_id("org-people-checkbox-#{orphan.id}"))
      |> click(test_id("org-people-checkbox-#{bob.id}"))

    # Click delete
    conn =
      conn
      |> click(test_id("org-people-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-confirm-delete-modal"))

    # Confirm
    conn =
      conn
      |> click(test_id("org-people-confirm-delete-btn"))
      |> wait_liveview()

    # Orphan and Bob gone, Alice remains
    conn
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice", timeout: 5_000)
    |> refute_has(test_id("org-people-table"), text: "Smith, Bob")
    |> refute_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "per-row delete button permanently deletes person", %{
    conn: conn,
    org: org,
    orphan: orphan
  } do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Click the per-row delete button on orphan
    conn =
      conn
      |> click(test_id("org-people-delete-person-#{orphan.id}"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-confirm-delete-modal"))

    # Confirm
    conn =
      conn
      |> click(test_id("org-people-confirm-delete-btn"))
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-people-table"), text: "Nobody, Orphan", timeout: 5_000)
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice")
  end

  test "cancel delete dismisses modal", %{conn: conn, org: org, orphan: orphan} do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Enter edit mode and select orphan
    conn =
      conn
      |> click(test_id("org-people-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-checkbox-#{orphan.id}"), timeout: 5_000)
      |> click(test_id("org-people-checkbox-#{orphan.id}"))
      |> click(test_id("org-people-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-confirm-delete-modal"))

    # Cancel
    conn =
      conn
      |> click(test_id("org-people-cancel-delete-btn"))
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-people-confirm-delete-modal"))
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "back navigation from person show returns to org people", %{
    conn: conn,
    org: org,
    alice: alice
  } do
    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Click Alice's name to navigate to person show
    conn =
      conn
      |> click(test_id("org-people-table") <> " a", text: "Smith, Alice")
      |> wait_liveview()

    # Should be on person show page
    conn = assert_has(conn, "h1", text: "Alice Smith")

    # Click back arrow
    conn =
      conn
      |> click("a[href='/org/#{org.id}/people']")
      |> wait_liveview()

    # Should be back on org people page
    conn
    |> assert_has(test_id("org-people-table"))
  end
end
```

- [ ] **Step 2: Run E2E tests**

Run: `mix test test/user_flows/org_manage_people_test.exs -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/org_manage_people_test.exs
git commit -m "Add E2E tests for org-level manage people page"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full precommit**

Run: `mix precommit`
Expected: All checks pass (compile, format, tests)

- [ ] **Step 2: Run all existing tests to check for regressions**

Run: `mix test`
Expected: All PASS, no regressions

- [ ] **Step 3: Commit any formatting fixes if needed**

```bash
git add -A
git commit -m "Fix formatting from precommit"
```
