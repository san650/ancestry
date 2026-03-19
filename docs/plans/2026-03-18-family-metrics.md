# Family Metrics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add family metrics (people count, photo count, generations, oldest person) to the right sidebar of the family show page.

**Architecture:** New `Ancestry.Families.Metrics` module computes all metrics via a single `compute/1` call. Results are passed as a `@metrics` assign through `SidePanelComponent`, rendered inline above the galleries list. All person mini cards are clickable to focus the tree view.

**Tech Stack:** Phoenix LiveView, Ecto queries, Tailwind CSS, ExMachina (tests)

---

### Task 1: Metrics Module — People Count & Photo Count

**Files:**
- Create: `lib/ancestry/families/metrics.ex`
- Test: `test/ancestry/families/metrics_test.exs`

**Step 1: Write the failing tests for people_count and photo_count**

```elixir
# test/ancestry/families/metrics_test.exs
defmodule Ancestry.Families.MetricsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families.Metrics

  describe "compute/1 counts" do
    test "empty family returns zero counts and nil metrics" do
      family = insert(:family)
      metrics = Metrics.compute(family.id)

      assert metrics.people_count == 0
      assert metrics.photo_count == 0
      assert metrics.generations == nil
      assert metrics.oldest_person == nil
    end

    test "counts people in the family" do
      family = insert(:family)
      person_a = insert(:person)
      person_b = insert(:person)
      Ancestry.People.add_to_family(person_a, family)
      Ancestry.People.add_to_family(person_b, family)

      metrics = Metrics.compute(family.id)
      assert metrics.people_count == 2
    end

    test "counts photos across all galleries in the family" do
      family = insert(:family)
      gallery_a = insert(:gallery, family: family)
      gallery_b = insert(:gallery, family: family)
      insert(:photo, gallery: gallery_a)
      insert(:photo, gallery: gallery_a)
      insert(:photo, gallery: gallery_b)

      metrics = Metrics.compute(family.id)
      assert metrics.photo_count == 3
    end

    test "does not count photos from other families" do
      family = insert(:family)
      other_family = insert(:family)
      gallery = insert(:gallery, family: family)
      other_gallery = insert(:gallery, family: other_family)
      insert(:photo, gallery: gallery)
      insert(:photo, gallery: other_gallery)

      metrics = Metrics.compute(family.id)
      assert metrics.photo_count == 1
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/families/metrics_test.exs`
Expected: FAIL — module `Ancestry.Families.Metrics` not found

**Step 3: Write minimal implementation**

```elixir
# lib/ancestry/families/metrics.ex
defmodule Ancestry.Families.Metrics do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Galleries.Photo

  def compute(family_id) do
    %{
      people_count: count_people(family_id),
      photo_count: count_photos(family_id),
      generations: nil,
      oldest_person: nil
    }
  end

  defp count_people(family_id) do
    Repo.one(
      from fm in FamilyMember,
        where: fm.family_id == ^family_id,
        select: count(fm.id)
    )
  end

  defp count_photos(family_id) do
    Repo.one(
      from p in Photo,
        join: g in Gallery,
        on: g.id == p.gallery_id,
        where: g.family_id == ^family_id,
        select: count(p.id)
    )
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/families/metrics_test.exs`
Expected: PASS (4 tests)

**Step 5: Commit**

```
feat: add Families.Metrics module with people and photo counts
```

---

### Task 2: Metrics Module — Oldest Person

**Files:**
- Modify: `lib/ancestry/families/metrics.ex`
- Modify: `test/ancestry/families/metrics_test.exs`

**Step 1: Write the failing tests for oldest_person**

Add to the existing test file:

```elixir
describe "compute/1 oldest_person" do
  test "returns oldest person by birth_year with age (alive)" do
    family = insert(:family)
    old = insert(:person, given_name: "Elder", birth_year: 1940)
    young = insert(:person, given_name: "Young", birth_year: 1990)
    Ancestry.People.add_to_family(old, family)
    Ancestry.People.add_to_family(young, family)

    metrics = Metrics.compute(family.id)
    assert metrics.oldest_person.person.id == old.id
    assert metrics.oldest_person.age == Date.utc_today().year - 1940
  end

  test "returns age at death for deceased person with death_year" do
    family = insert(:family)
    deceased = insert(:person, given_name: "Gone", birth_year: 1900, death_year: 1980, deceased: true)
    Ancestry.People.add_to_family(deceased, family)

    metrics = Metrics.compute(family.id)
    assert metrics.oldest_person.person.id == deceased.id
    assert metrics.oldest_person.age == 80
  end

  test "skips deceased person without death_year, picks next eligible" do
    family = insert(:family)
    no_death_year = insert(:person, given_name: "Unknown", birth_year: 1880, deceased: true)
    has_death_year = insert(:person, given_name: "Known", birth_year: 1900, death_year: 1970, deceased: true)
    Ancestry.People.add_to_family(no_death_year, family)
    Ancestry.People.add_to_family(has_death_year, family)

    metrics = Metrics.compute(family.id)
    assert metrics.oldest_person.person.id == has_death_year.id
    assert metrics.oldest_person.age == 70
  end

  test "returns nil when no person has a birth_year" do
    family = insert(:family)
    insert(:person) |> then(&Ancestry.People.add_to_family(&1, family))

    metrics = Metrics.compute(family.id)
    assert metrics.oldest_person == nil
  end

  test "adjusts age by month when birth_month is available" do
    family = insert(:family)
    today = Date.utc_today()
    # Person born in December of a past year — hasn't had birthday this year yet
    person = insert(:person, birth_year: today.year - 50, birth_month: 12)
    Ancestry.People.add_to_family(person, family)

    metrics = Metrics.compute(family.id)

    expected_age = if today.month >= 12, do: 50, else: 49
    assert metrics.oldest_person.age == expected_age
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/families/metrics_test.exs`
Expected: FAIL — oldest_person is always nil

**Step 3: Implement oldest_person**

Update `compute/1` to call `find_oldest_person(family_id)` and add these private functions to `lib/ancestry/families/metrics.ex`:

```elixir
alias Ancestry.People.Person

# In compute/1, replace `oldest_person: nil` with:
#   oldest_person: find_oldest_person(family_id)

defp find_oldest_person(family_id) do
  family_member_ids = family_member_ids_query(family_id)

  candidates =
    Repo.all(
      from p in Person,
        where: p.id in subquery(family_member_ids),
        where: not is_nil(p.birth_year),
        where: p.deceased == false or (p.deceased == true and not is_nil(p.death_year)),
        order_by: [asc: p.birth_year, asc_nulls_last: p.birth_month, asc_nulls_last: p.birth_day],
        limit: 1
    )

  case candidates do
    [person] ->
      age = calculate_age(person)
      %{person: person, age: age}

    [] ->
      nil
  end
end

defp calculate_age(%Person{deceased: true, birth_year: by, death_year: dy} = p) do
  base = dy - by
  adjust_age(base, p.birth_month, p.birth_day, p.death_month, p.death_day)
end

defp calculate_age(%Person{birth_year: by} = p) do
  today = Date.utc_today()
  base = today.year - by
  adjust_age(base, p.birth_month, p.birth_day, today.month, today.day)
end

defp adjust_age(base, nil, _bd, _em, _ed), do: base
defp adjust_age(base, bm, bd, end_month, end_day) do
  bd = bd || 1
  end_day = end_day || 1
  if {end_month, end_day} < {bm, bd}, do: base - 1, else: base
end

defp family_member_ids_query(family_id) do
  from fm in FamilyMember,
    where: fm.family_id == ^family_id,
    select: fm.person_id
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/families/metrics_test.exs`
Expected: PASS (all tests)

**Step 5: Commit**

```
feat: add oldest person metric to Families.Metrics
```

---

### Task 3: Metrics Module — Longest Descendant Line (Generations)

**Files:**
- Modify: `lib/ancestry/families/metrics.ex`
- Modify: `test/ancestry/families/metrics_test.exs`

**Step 1: Write the failing tests for generations**

Add to the existing test file:

```elixir
describe "compute/1 generations" do
  test "returns nil when fewer than 2 people" do
    family = insert(:family)
    person = insert(:person)
    Ancestry.People.add_to_family(person, family)

    metrics = Metrics.compute(family.id)
    assert metrics.generations == nil
  end

  test "3-generation chain returns count 3 with correct root and leaf" do
    family = insert(:family)
    grandparent = insert(:person, given_name: "Grand")
    parent = insert(:person, given_name: "Parent")
    child = insert(:person, given_name: "Child")

    Ancestry.People.add_to_family(grandparent, family)
    Ancestry.People.add_to_family(parent, family)
    Ancestry.People.add_to_family(child, family)

    Ancestry.Relationships.create_relationship(grandparent, parent, "parent")
    Ancestry.Relationships.create_relationship(parent, child, "parent")

    metrics = Metrics.compute(family.id)
    assert metrics.generations.count == 3
    assert metrics.generations.root.id == grandparent.id
    assert metrics.generations.leaf.id == child.id
  end

  test "picks the longest branch when multiple exist" do
    family = insert(:family)
    root = insert(:person, given_name: "Root")
    mid = insert(:person, given_name: "Mid")
    leaf_short = insert(:person, given_name: "ShortLeaf")
    leaf_long = insert(:person, given_name: "LongLeaf")

    for p <- [root, mid, leaf_short, leaf_long], do: Ancestry.People.add_to_family(p, family)

    Ancestry.Relationships.create_relationship(root, mid, "parent")
    Ancestry.Relationships.create_relationship(root, leaf_short, "parent")
    Ancestry.Relationships.create_relationship(mid, leaf_long, "parent")

    metrics = Metrics.compute(family.id)
    assert metrics.generations.count == 3
    assert metrics.generations.root.id == root.id
    assert metrics.generations.leaf.id == leaf_long.id
  end

  test "scopes to family members only — ignores children outside the family" do
    family = insert(:family)
    root = insert(:person, given_name: "Root")
    child_in = insert(:person, given_name: "InFamily")
    child_out = insert(:person, given_name: "OutFamily")
    grandchild = insert(:person, given_name: "Grandchild")

    Ancestry.People.add_to_family(root, family)
    Ancestry.People.add_to_family(child_in, family)
    # child_out is NOT added to family
    Ancestry.People.add_to_family(grandchild, family)

    Ancestry.Relationships.create_relationship(root, child_in, "parent")
    Ancestry.Relationships.create_relationship(root, child_out, "parent")
    Ancestry.Relationships.create_relationship(child_out, grandchild, "parent")

    metrics = Metrics.compute(family.id)
    # root -> child_in is 2 generations
    # root -> child_out -> grandchild would be 3, but child_out is not in family so chain breaks
    assert metrics.generations.count == 2
    assert metrics.generations.root.id == root.id
    assert metrics.generations.leaf.id == child_in.id
  end

  test "returns nil when people exist but no parent relationships" do
    family = insert(:family)
    a = insert(:person)
    b = insert(:person)
    Ancestry.People.add_to_family(a, family)
    Ancestry.People.add_to_family(b, family)

    metrics = Metrics.compute(family.id)
    assert metrics.generations == nil
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/families/metrics_test.exs`
Expected: FAIL — generations is always nil

**Step 3: Implement longest descendant line**

Update `compute/1` to call `find_longest_line(family_id)` and add these private functions to `lib/ancestry/families/metrics.ex`:

```elixir
alias Ancestry.Relationships.Relationship

# In compute/1, replace `generations: nil` with:
#   generations: find_longest_line(family_id)

defp find_longest_line(family_id) do
  member_ids = MapSet.new(Repo.all(family_member_ids_query(family_id)))

  if MapSet.size(member_ids) < 2 do
    nil
  else
    # Build a children map scoped to family members
    parent_child_pairs =
      Repo.all(
        from r in Relationship,
          where: r.type == "parent",
          where: r.person_a_id in ^MapSet.to_list(member_ids),
          where: r.person_b_id in ^MapSet.to_list(member_ids),
          select: {r.person_a_id, r.person_b_id}
      )

    children_map =
      Enum.group_by(parent_child_pairs, fn {parent_id, _} -> parent_id end, fn {_, child_id} -> child_id end)

    parent_set = MapSet.new(parent_child_pairs, fn {_, child_id} -> child_id end)

    # Root ancestors: family members who are in the relationship graph but have no parents (within family)
    roots =
      member_ids
      |> Enum.filter(&Map.has_key?(children_map, &1))
      |> Enum.reject(&MapSet.member?(parent_set, &1))

    if roots == [] do
      nil
    else
      # DFS from each root to find longest path
      {best_count, best_root_id, best_leaf_id} =
        Enum.reduce(roots, {0, nil, nil}, fn root_id, best ->
          {depth, leaf_id} = dfs_longest(root_id, children_map)
          if depth > elem(best, 0), do: {depth, root_id, leaf_id}, else: best
        end)

      if best_count >= 2 do
        people_by_id = load_people_by_ids([best_root_id, best_leaf_id])
        %{
          count: best_count,
          root: Map.get(people_by_id, best_root_id),
          leaf: Map.get(people_by_id, best_leaf_id)
        }
      else
        nil
      end
    end
  end
end

defp dfs_longest(person_id, children_map) do
  case Map.get(children_map, person_id, []) do
    [] ->
      {1, person_id}

    children ->
      children
      |> Enum.map(fn child_id -> dfs_longest(child_id, children_map) end)
      |> Enum.max_by(fn {depth, _} -> depth end)
      |> then(fn {depth, leaf_id} -> {depth + 1, leaf_id} end)
  end
end

defp load_people_by_ids(ids) do
  ids = Enum.uniq(ids)

  Repo.all(from p in Person, where: p.id in ^ids)
  |> Map.new(fn p -> {p.id, p} end)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/families/metrics_test.exs`
Expected: PASS (all tests)

**Step 5: Commit**

```
feat: add longest descendant line (generations) metric
```

---

### Task 4: Side Panel UI — Metrics Section

**Files:**
- Modify: `lib/web/live/family_live/side_panel_component.ex`
- Modify: `lib/web/live/family_live/show.ex` (mount + callbacks)
- Modify: `lib/web/live/family_live/show.html.heex` (pass metrics to side panel)

**Step 1: Update show.ex to compute and pass metrics**

In `lib/web/live/family_live/show.ex`:

Add alias at top:
```elixir
alias Ancestry.Families.Metrics
```

In `mount/3`, after `galleries = Galleries.list_galleries(family_id)`, add:
```elixir
metrics = Metrics.compute(family_id)
```

Add `|> assign(:metrics, metrics)` to the socket pipeline.

In `handle_event("link_person", ...)` success branch, after `people = People.list_people_for_family(family.id)`, add:
```elixir
metrics = Metrics.compute(family.id)
```
And add `|> assign(:metrics, metrics)` to the socket pipeline.

In `handle_info({:relationship_saved, ...})`, after `people = People.list_people_for_family(family.id)`, add:
```elixir
metrics = Metrics.compute(family.id)
```
And add `|> assign(:metrics, metrics)` to the socket pipeline.

In `handle_event("save_gallery", ...)` success branch, after `galleries = Galleries.list_galleries(...)`, add:
```elixir
metrics = Metrics.compute(socket.assigns.family.id)
```
And add `|> assign(:metrics, metrics)` to the socket pipeline.

In `handle_event("confirm_delete_gallery", ...)`, after `galleries = Galleries.list_galleries(...)`, add:
```elixir
metrics = Metrics.compute(socket.assigns.family.id)
```
And add `|> assign(:metrics, metrics)` to the socket pipeline.

**Step 2: Pass metrics to SidePanelComponent in show.html.heex**

In `lib/web/live/family_live/show.html.heex`, update the `SidePanelComponent` invocation to add:
```elixir
metrics={@metrics}
```

**Step 3: Update SidePanelComponent to render metrics**

Replace the content of `lib/web/live/family_live/side_panel_component.ex` with the metrics section above galleries. The component accepts a new `@metrics` assign.

```elixir
defmodule Web.FamilyLive.SidePanelComponent do
  use Web, :live_component

  alias Ancestry.People.Person
  alias Web.FamilyLive.GalleryListComponent
  alias Web.FamilyLive.PeopleListComponent

  @impl true
  def render(assigns) do
    ~H"""
    <aside id={@id} class="bg-base-100 flex flex-col p-4 gap-6">
      <%!-- Metrics Section --%>
      <%= if @metrics.people_count > 0 do %>
        <div class="space-y-4">
          <%!-- People & Photo counts --%>
          <div class="grid grid-cols-2 gap-3">
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-people-count")}
            >
              <.icon name="hero-users" class="w-5 h-5 text-primary mb-1" />
              <span class="text-2xl font-bold text-base-content">{@metrics.people_count}</span>
              <span class="text-xs text-base-content/50">Members</span>
            </div>
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-photo-count")}
            >
              <.icon name="hero-photo" class="w-5 h-5 text-secondary mb-1" />
              <span class="text-2xl font-bold text-base-content">{@metrics.photo_count}</span>
              <span class="text-xs text-base-content/50">Photos</span>
            </div>
          </div>

          <%!-- Generations --%>
          <%= if @metrics.generations do %>
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-generations")}
            >
              <span class="text-xs text-base-content/50 uppercase tracking-wider mb-2">
                Lineage
              </span>
              <.metric_person_card person={@metrics.generations.root} label="Root ancestor" />
              <div class="flex flex-col items-center my-1">
                <div class="w-px h-3 bg-base-content/20"></div>
                <span class="text-sm font-semibold text-primary py-0.5">
                  {@metrics.generations.count} generations
                </span>
                <div class="w-px h-3 bg-base-content/20"></div>
              </div>
              <.metric_person_card person={@metrics.generations.leaf} label="Latest descendant" />
            </div>
          <% end %>

          <%!-- Oldest Person --%>
          <%= if @metrics.oldest_person do %>
            <div
              class="flex flex-col items-center p-3 rounded-xl bg-base-200/50"
              {test_id("metric-oldest-person")}
            >
              <span class="text-xs text-base-content/50 uppercase tracking-wider mb-2">
                Oldest Record
              </span>
              <.metric_person_card
                person={@metrics.oldest_person.person}
                label={age_label(@metrics.oldest_person)}
              />
            </div>
          <% end %>
        </div>

        <div class="border-t border-base-200"></div>
      <% end %>

      <.live_component
        module={GalleryListComponent}
        id="gallery-list"
        galleries={@galleries}
        family_id={@family_id}
      />

      <div class="border-t border-base-200"></div>

      <.live_component
        module={PeopleListComponent}
        id="people-list"
        people={@people}
        family_id={@family_id}
        focus_person_id={@focus_person_id}
      />
    </aside>
    """
  end

  attr :person, :map, required: true
  attr :label, :string, required: true

  defp metric_person_card(assigns) do
    ~H"""
    <button
      phx-click="focus_person"
      phx-value-id={@person.id}
      class="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-base-300/50 transition-colors w-full group"
    >
      <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <span class="text-xs font-semibold text-primary">
            {initials(@person)}
          </span>
        <% end %>
      </div>
      <div class="min-w-0 text-left">
        <p class="text-sm font-medium text-base-content truncate group-hover:text-primary transition-colors">
          {Person.display_name(@person)}
        </p>
        <p class="text-xs text-base-content/50">{@label}</p>
      </div>
    </button>
    """
  end

  defp initials(%Person{given_name: g, surname: s}) do
    [g, s]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp age_label(%{person: person, age: age}) do
    if person.deceased do
      "was #{age} years"
    else
      "#{age} years"
    end
  end
end
```

**Step 4: Run the full test suite**

Run: `mix test`
Expected: PASS (all existing tests still pass)

**Step 5: Commit**

```
feat: render family metrics in sidebar above galleries
```

---

### Task 5: Metrics Refresh on Data Changes

**Files:**
- Modify: `lib/web/live/family_live/show.ex`

This task is about ensuring metrics recompute correctly. The changes were described in Task 4 Step 1, but let's verify by running through scenarios manually.

**Step 1: Verify mount loads metrics**

Run: `iex -S mix phx.server`
Navigate to a family page. Confirm metrics are visible in the sidebar.

**Step 2: Run existing tests to ensure no regressions**

Run: `mix test`
Expected: PASS

**Step 3: Commit (if any adjustments were needed)**

```
fix: ensure metrics refresh on gallery and relationship changes
```

---

### Task 6: User Flow E2E Test

**Files:**
- Create: `test/user_flows/family_metrics_test.exs`

**Step 1: Write the E2E test**

```elixir
# test/user_flows/family_metrics_test.exs
defmodule Web.UserFlows.FamilyMetricsTest do
  use Web.E2ECase

  # Given a family with several people, relationships, galleries with photos
  # When the user navigates to the family show page
  # Then the sidebar shows the people count and photo count
  # And the generations metric shows root and leaf person cards with the generation count
  # And the oldest person card is shown with their age
  #
  # When the user clicks the oldest person card
  # Then the tree view loads that person
  #
  # When the user clicks the root ancestor card in the generations metric
  # Then the tree view loads that person

  setup do
    family = insert(:family, name: "Metrics Family")

    # 3-generation chain: grandpa -> parent -> child
    grandpa = insert(:person, given_name: "George", surname: "Elder", birth_year: 1940)
    parent = insert(:person, given_name: "Alice", surname: "Elder", birth_year: 1970)
    child = insert(:person, given_name: "Charlie", surname: "Elder", birth_year: 2000)

    for p <- [grandpa, parent, child], do: Ancestry.People.add_to_family(p, family)

    Ancestry.Relationships.create_relationship(grandpa, parent, "parent")
    Ancestry.Relationships.create_relationship(parent, child, "parent")

    # A gallery with photos
    gallery = insert(:gallery, family: family, name: "Summer 2025")
    insert(:photo, gallery: gallery)
    insert(:photo, gallery: gallery)

    %{family: family, grandpa: grandpa, parent: parent, child: child}
  end

  test "displays metrics and navigates via person cards", %{
    conn: conn,
    family: family,
    grandpa: grandpa,
    child: child
  } do
    # Navigate to the family show page
    conn =
      conn
      |> visit(~p"/families/#{family.id}")
      |> wait_liveview()

    # Verify people count
    conn
    |> assert_has(test_id("metric-people-count"), text: "3")

    # Verify photo count
    conn
    |> assert_has(test_id("metric-photo-count"), text: "2")

    # Verify generations metric
    conn
    |> assert_has(test_id("metric-generations"), text: "3 generations")
    |> assert_has(test_id("metric-generations"), text: "George Elder")
    |> assert_has(test_id("metric-generations"), text: "Charlie Elder")

    # Verify oldest person
    conn
    |> assert_has(test_id("metric-oldest-person"), text: "George Elder")
    |> assert_has(test_id("metric-oldest-person"), text: "years")

    # Click oldest person card — should load tree view for George
    conn =
      conn
      |> click(test_id("metric-oldest-person") <> " button[phx-click='focus_person']")
      |> wait_liveview()

    # Verify URL has person param for grandpa
    conn
    |> assert_has("[data-person-id='#{grandpa.id}']")

    # Navigate back to family show (no person focused)
    conn =
      conn
      |> visit(~p"/families/#{family.id}")
      |> wait_liveview()

    # Click root ancestor in generations — should load tree for George
    conn =
      conn
      |> click(test_id("metric-generations") <> " button[phx-click='focus_person'][phx-value-id='#{grandpa.id}']")
      |> wait_liveview()

    conn
    |> assert_has("[data-person-id='#{grandpa.id}']")

    # Navigate back and click leaf descendant
    conn =
      conn
      |> visit(~p"/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("metric-generations") <> " button[phx-click='focus_person'][phx-value-id='#{child.id}']")
      |> wait_liveview()

    conn
    |> assert_has("[data-person-id='#{child.id}']")
  end
end
```

**Step 2: Run the E2E test**

Run: `mix test test/user_flows/family_metrics_test.exs`
Expected: PASS

**Step 3: Commit**

```
test: add family metrics user flow E2E test
```

---

### Task 7: Final Verification

**Step 1: Run precommit checks**

Run: `mix precommit`
Expected: PASS — no warnings, no formatting issues, all tests pass

**Step 2: Fix any issues found by precommit**

If there are formatting or warning issues, fix them.

**Step 3: Final commit (if any fixes)**

```
chore: fix formatting/warnings from precommit
```
