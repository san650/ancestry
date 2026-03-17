# Fix Children Not Shown on Parent's Show Page

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix bug where children with two unlinked parents are invisible on the parent's show page.

**Architecture:** Replace per-partner `get_children_of_pair` N+1 queries and `get_solo_children` with a single `get_children_with_coparents/1` query. Group results in memory into three buckets (partner children, unlinked co-parent children, solo children). Add a new template section for the unlinked co-parent bucket.

**Tech Stack:** Elixir, Ecto, Phoenix LiveView

**Spec:** `docs/bugfix/specs/2026-03-16-children-not-shown-on-parent-page-design.md`

---

### Task 1: Add `get_children_with_coparents/1` query with tests

**Files:**
- Modify: `lib/ancestry/relationships.ex` (after `get_children/1` at ~line 101)
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing tests**

Add this describe block at the end of `test/ancestry/relationships_test.exs` (before the final `defp family_fixture`):

```elixir
describe "get_children_with_coparents/1" do
  test "returns {child, coparent} when child has two parents" do
    family = family_fixture()
    {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
    {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
    {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

    {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

    results = Relationships.get_children_with_coparents(father.id)
    assert [{returned_child, returned_coparent}] = results
    assert returned_child.id == child.id
    assert returned_coparent.id == mother.id
  end

  test "returns {child, nil} when child has only one parent" do
    family = family_fixture()
    {:ok, parent} = People.create_person(family, %{given_name: "Dad", surname: "D"})
    {:ok, child} = People.create_person(family, %{given_name: "Solo", surname: "D"})

    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

    results = Relationships.get_children_with_coparents(parent.id)
    assert [{returned_child, nil}] = results
    assert returned_child.id == child.id
  end

  test "returns multiple children with different co-parents" do
    family = family_fixture()
    {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
    {:ok, mother1} = People.create_person(family, %{given_name: "Mom1", surname: "D"})
    {:ok, mother2} = People.create_person(family, %{given_name: "Mom2", surname: "D"})
    {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
    {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})
    {:ok, solo} = People.create_person(family, %{given_name: "Solo", surname: "D"})

    {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother1, child1, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mother2, child2, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(father, solo, "parent", %{role: "father"})

    results = Relationships.get_children_with_coparents(father.id)
    assert length(results) == 3

    result_map = Map.new(results, fn {child, coparent} -> {child.id, coparent} end)
    assert result_map[child1.id].id == mother1.id
    assert result_map[child2.id].id == mother2.id
    assert result_map[solo.id] == nil
  end

  test "returns empty list when person has no children" do
    family = family_fixture()
    {:ok, person} = People.create_person(family, %{given_name: "Lonely", surname: "D"})

    assert Relationships.get_children_with_coparents(person.id) == []
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/relationships_test.exs --seed 0 2>&1 | tail -20`
Expected: Compilation error — `get_children_with_coparents/1` is undefined

**Step 3: Write the implementation**

Add this function to `lib/ancestry/relationships.ex` after the existing `get_children/1` function (after line 101):

```elixir
@doc """
Returns all children of person_id with their co-parent (if any).
Returns `[{child, coparent | nil}]`.
"""
def get_children_with_coparents(person_id) do
  from(child in Person,
    join: r1 in Relationship,
    on: r1.person_b_id == child.id and r1.person_a_id == ^person_id and r1.type == "parent",
    left_join: r2 in Relationship,
    on: r2.person_b_id == child.id and r2.type == "parent" and r2.person_a_id != ^person_id,
    left_join: coparent in Person,
    on: coparent.id == r2.person_a_id,
    select: {child, coparent}
  )
  |> Repo.all()
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/relationships_test.exs --seed 0 2>&1 | tail -5`
Expected: All tests pass (0 failures)

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "Add get_children_with_coparents/1 query

Single query replaces the per-partner get_children_of_pair N+1 loop
and get_solo_children. Returns each child with their co-parent (or nil)."
```

---

### Task 2: Rewrite `load_relationships/2` to use new query and group in memory

**Files:**
- Modify: `lib/web/live/person_live/show.ex:380-422` (`load_relationships/2`)

**Step 1: Write the failing test**

Add to `test/web/live/person_live/relationships_test.exs`:

```elixir
test "displays children with unlinked co-parent", %{conn: conn, family: family} do
  {:ok, father} =
    People.create_person(family, %{given_name: "Dad", surname: "Doe", gender: "male"})

  {:ok, mother} =
    People.create_person(family, %{given_name: "Mom", surname: "Doe", gender: "female"})

  {:ok, child} =
    People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

  # Both are parents of child, but NOT linked as partners
  {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

  # Visit father's page — child should be visible in coparent section
  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{father.id}")
  assert has_element?(view, "#coparent-children-#{mother.id}")
  assert render(view) =~ "Kid"

  # Visit mother's page — child should also be visible
  {:ok, view2, _html} = live(conn, ~p"/families/#{family.id}/members/#{mother.id}")
  assert has_element?(view2, "#coparent-children-#{father.id}")
  assert render(view2) =~ "Kid"
end

test "child with partnered parents appears under partner group not coparent section", %{
  conn: conn,
  family: family,
  person: person
} do
  {:ok, spouse} =
    People.create_person(family, %{given_name: "Jane", surname: "Doe", gender: "female"})

  {:ok, child} =
    People.create_person(family, %{given_name: "Kid", surname: "Doe", gender: "male"})

  {:ok, _} =
    Relationships.create_relationship(person, spouse, "partner", %{marriage_year: 2020})

  {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(spouse, child, "parent", %{role: "mother"})

  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")

  # Child should be under partner group, NOT in coparent section
  assert has_element?(view, "#partner-group-#{spouse.id}")
  refute has_element?(view, "#coparent-children-#{spouse.id}")
  assert render(view) =~ "Kid"
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/web/live/person_live/relationships_test.exs --seed 0 2>&1 | tail -20`
Expected: The "displays children with unlinked co-parent" test fails — no `#coparent-children-*` element exists

**Step 3: Rewrite `load_relationships/2`**

Replace the `load_relationships/2` function in `lib/web/live/person_live/show.ex` (lines 380-422). The new version:

```elixir
defp load_relationships(socket, person) do
  partners = Relationships.get_partners(person.id)
  ex_partners = Relationships.get_ex_partners(person.id)
  all_partner_rels = partners ++ ex_partners

  children_with_coparents = Relationships.get_children_with_coparents(person.id)

  partner_ids = MapSet.new(all_partner_rels, fn {p, _rel} -> p.id end)

  # Group children into three buckets
  {partner_child_map, coparent_map, solo_children} =
    Enum.reduce(children_with_coparents, {%{}, %{}, []}, fn
      {child, nil}, {pc, cp, solo} ->
        {pc, cp, [child | solo]}

      {child, coparent}, {pc, cp, solo} ->
        if MapSet.member?(partner_ids, coparent.id) do
          {Map.update(pc, coparent.id, [child], &[child | &1]), cp, solo}
        else
          {pc, Map.update(cp, coparent.id, {coparent, [child]}, fn {cp_person, kids} -> {cp_person, [child | kids]} end), solo}
        end
    end)

  # Attach children to partner tuples
  partner_children =
    Enum.map(all_partner_rels, fn {partner, rel} ->
      children = Map.get(partner_child_map, partner.id, [])
      {partner, rel, children}
    end)

  # Convert coparent map to list of {coparent, [children]}
  coparent_children =
    coparent_map
    |> Map.values()
    |> Enum.map(fn {coparent, children} -> {coparent, Enum.reverse(children)} end)

  parents = Relationships.get_parents(person.id)

  parents_marriage =
    case parents do
      [{p1, _}, {p2, _}] ->
        case Relationships.get_partners(p1.id) do
          partners ->
            Enum.find_value(partners, fn {partner, rel} ->
              if partner.id == p2.id, do: rel
            end)
        end

      _ ->
        nil
    end

  socket
  |> assign(:parents, parents)
  |> assign(:parents_marriage, parents_marriage)
  |> assign(:partner_children, partner_children)
  |> assign(:coparent_children, coparent_children)
  |> assign(:siblings, Relationships.get_siblings(person.id))
  |> assign(:solo_children, Enum.reverse(solo_children))
  |> assign(:adding_relationship, nil)
  |> assign(:search_query, "")
  |> assign(:search_results, [])
  |> assign(:selected_person, nil)
  |> assign(:relationship_form, nil)
  |> assign(:converting_to_ex, nil)
  |> assign(:ex_form, nil)
  |> assign(:editing_relationship, nil)
  |> assign(:edit_relationship_form, nil)
  |> assign(:adding_partner_id, nil)
end
```

**Step 4: Run tests — they will still fail because the template doesn't have the coparent section yet**

Run: `mix test test/web/live/person_live/relationships_test.exs --seed 0 2>&1 | tail -20`
Expected: Still fails on the `#coparent-children-*` element check (template not updated yet). But existing tests should still pass since `@partner_children` and `@solo_children` shapes are preserved.

**Step 5: Add coparent_children section to the template**

In `lib/web/live/person_live/show.html.heex`, insert the following block between the partner group closing `<% end %>` (line 419) and the solo children section comment (line 421):

```heex
          <%!-- Children with unlinked co-parent --%>
          <%= for {coparent, children} <- @coparent_children do %>
            <div
              id={"coparent-children-#{coparent.id}"}
              class="rounded-xl border border-base-300 p-4 space-y-3"
            >
              <p class="text-xs font-medium text-base-content/40 uppercase tracking-wide">
                Children with
              </p>
              <.link
                navigate={~p"/families/#{@family.id}/members/#{coparent.id}"}
                class="rounded-lg transition-colors hover:bg-base-200"
              >
                <.person_card person={coparent} highlighted={false} />
              </.link>
              <div class="pl-4 border-l-2 border-base-200 space-y-1 mt-2">
                <%= for child <- children do %>
                  <.link
                    navigate={~p"/families/#{@family.id}/members/#{child.id}"}
                    class="rounded-lg transition-colors hover:bg-base-200"
                  >
                    <.person_card person={child} highlighted={false} />
                  </.link>
                <% end %>
              </div>
            </div>
          <% end %>
```

**Step 6: Run all tests to verify everything passes**

Run: `mix test test/web/live/person_live/relationships_test.exs --seed 0 2>&1 | tail -10`
Expected: All tests pass (0 failures)

**Step 7: Run full test suite**

Run: `mix test 2>&1 | tail -5`
Expected: All tests pass

**Step 8: Commit**

```bash
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex test/web/live/person_live/relationships_test.exs
git commit -m "Fix children not shown when parents are unlinked

Replace per-partner get_children_of_pair N+1 and get_solo_children
with single get_children_with_coparents query. Group in memory into
partner children, unlinked co-parent children, and solo children.
Add coparent_children template section."
```

---

### Task 3: Run precommit and verify

**Step 1: Run precommit**

Run: `mix precommit 2>&1 | tail -20`
Expected: All checks pass (compile, deps, format, tests)

**Step 2: If any formatting issues, fix and commit**

```bash
git add -A
git commit -m "Fix formatting from precommit"
```
