# Family-Scoped Tree View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Filter the TreeView to only show people who are members of the current family, so that a person shared across multiple families only shows family-scoped ancestors and descendants.

**Architecture:** Add an optional `family_id` keyword option to each `Relationships.get_*` query function. When provided, queries join on `family_members` to ensure returned people belong to that family. `PersonTree` accepts `family_id` and threads it through all recursive calls. Kinship remains unchanged (global traversal).

**Tech Stack:** Ecto queries with optional joins on `family_members`, PersonTree struct changes, FamilyLive.Show wiring.

---

### Task 1: Add family_id filtering to Relationships.get_parents/2

**Files:**
- Modify: `lib/ancestry/relationships.ex:94-102` (get_parents)
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing test**

Add a new test at the end of the `describe "get_parents/1"` block in `test/ancestry/relationships_test.exs`:

```elixir
test "filters parents by family_id" do
  family1 = family_fixture(%{name: "Family 1"})
  family2 = family_fixture(%{name: "Family 2"})

  {:ok, father} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
  {:ok, mother} = People.create_person(family2, %{given_name: "Mom", surname: "D"})
  {:ok, child} = People.create_person(family1, %{given_name: "Kid", surname: "D"})
  # Also add child to family2
  People.add_to_family(child, family2)

  {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

  # Without family_id — returns both parents (global)
  assert length(Relationships.get_parents(child.id)) == 2

  # With family_id — only returns the parent who is in that family
  family1_parents = Relationships.get_parents(child.id, family_id: family1.id)
  assert length(family1_parents) == 1
  assert {parent, _rel} = hd(family1_parents)
  assert parent.id == father.id

  family2_parents = Relationships.get_parents(child.id, family_id: family2.id)
  assert length(family2_parents) == 1
  assert {parent, _rel} = hd(family2_parents)
  assert parent.id == mother.id
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: FAIL — `get_parents/2` doesn't accept opts yet.

**Step 3: Write minimal implementation**

In `lib/ancestry/relationships.ex`, replace `get_parents/1` with:

```elixir
def get_parents(person_id, opts \\ []) do
  query =
    from(r in Relationship,
      join: p in Person,
      on: p.id == r.person_a_id,
      where: r.person_b_id == ^person_id and r.type == "parent",
      select: {p, r}
    )

  query = maybe_filter_by_family(query, :person_a_id, opts[:family_id])

  Repo.all(query)
end
```

Add the shared helper at the bottom of the module (before the last `end`):

```elixir
defp maybe_filter_by_family(query, _field, nil), do: query

defp maybe_filter_by_family(query, field, family_id) do
  case field do
    :person_a_id ->
      from [r, p] in query,
        join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^family_id

    :person_b_id ->
      from [r, p] in query,
        join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^family_id
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "feat: add family_id filtering to Relationships.get_parents/2"
```

---

### Task 2: Add family_id filtering to Relationships.get_children/2

**Files:**
- Modify: `lib/ancestry/relationships.ex:107-116` (get_children)
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing test**

Add to the `describe "get_children/1"` block:

```elixir
test "filters children by family_id" do
  family1 = family_fixture(%{name: "Family 1"})
  family2 = family_fixture(%{name: "Family 2"})

  {:ok, parent} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
  People.add_to_family(parent, family2)
  {:ok, child1} = People.create_person(family1, %{given_name: "Kid1", surname: "D"})
  {:ok, child2} = People.create_person(family2, %{given_name: "Kid2", surname: "D"})

  {:ok, _} = Relationships.create_relationship(parent, child1, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(parent, child2, "parent", %{role: "father"})

  # Without family_id — returns both
  assert length(Relationships.get_children(parent.id)) == 2

  # With family_id — only returns children in that family
  f1_children = Relationships.get_children(parent.id, family_id: family1.id)
  assert length(f1_children) == 1
  assert hd(f1_children).id == child1.id

  f2_children = Relationships.get_children(parent.id, family_id: family2.id)
  assert length(f2_children) == 1
  assert hd(f2_children).id == child2.id
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: FAIL

**Step 3: Write minimal implementation**

Replace `get_children/1`:

```elixir
def get_children(person_id, opts \\ []) do
  query =
    from(r in Relationship,
      join: p in Person,
      on: p.id == r.person_b_id,
      where: r.person_a_id == ^person_id and r.type == "parent",
      order_by: [asc_nulls_last: p.birth_year, asc: p.id],
      select: p
    )

  query = maybe_filter_by_family(query, :person_b_id, opts[:family_id])

  Repo.all(query)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "feat: add family_id filtering to Relationships.get_children/2"
```

---

### Task 3: Add family_id filtering to Relationships.get_partners/2 and get_ex_partners/2

**Files:**
- Modify: `lib/ancestry/relationships.ex:138-167` (get_partners, get_ex_partners, get_relationship_partners)
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing tests**

Add to the `describe "get_partners/1"` block:

```elixir
test "filters partners by family_id" do
  family1 = family_fixture(%{name: "Family 1"})
  family2 = family_fixture(%{name: "Family 2"})

  {:ok, person} = People.create_person(family1, %{given_name: "Person", surname: "P"})
  People.add_to_family(person, family2)
  {:ok, partner1} = People.create_person(family1, %{given_name: "Partner1", surname: "P"})
  {:ok, partner2} = People.create_person(family2, %{given_name: "Partner2", surname: "P"})

  {:ok, _} = Relationships.create_relationship(person, partner1, "partner")
  {:ok, _} = Relationships.create_relationship(person, partner2, "partner")

  # Without family_id — returns both
  assert length(Relationships.get_partners(person.id)) == 2

  # With family_id — only returns partner in that family
  f1_partners = Relationships.get_partners(person.id, family_id: family1.id)
  assert length(f1_partners) == 1
  assert {p, _} = hd(f1_partners)
  assert p.id == partner1.id
end
```

Add to the `describe "get_ex_partners/1"` block:

```elixir
test "filters ex_partners by family_id" do
  family1 = family_fixture(%{name: "Family 1"})
  family2 = family_fixture(%{name: "Family 2"})

  {:ok, person} = People.create_person(family1, %{given_name: "Person", surname: "P"})
  People.add_to_family(person, family2)
  {:ok, ex1} = People.create_person(family1, %{given_name: "Ex1", surname: "P"})
  {:ok, ex2} = People.create_person(family2, %{given_name: "Ex2", surname: "P"})

  {:ok, _} = Relationships.create_relationship(person, ex1, "ex_partner", %{marriage_year: 2010, divorce_year: 2015})
  {:ok, _} = Relationships.create_relationship(person, ex2, "ex_partner", %{marriage_year: 2012, divorce_year: 2016})

  # Without family_id — returns both
  assert length(Relationships.get_ex_partners(person.id)) == 2

  # With family_id — only returns ex in that family
  f1_exes = Relationships.get_ex_partners(person.id, family_id: family1.id)
  assert length(f1_exes) == 1
  assert {ex, _} = hd(f1_exes)
  assert ex.id == ex1.id
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: FAIL

**Step 3: Write minimal implementation**

Update `get_partners`, `get_ex_partners`, and `get_relationship_partners`:

```elixir
def get_partners(person_id, opts \\ []) do
  get_relationship_partners(person_id, "partner", opts)
end

def get_ex_partners(person_id, opts \\ []) do
  get_relationship_partners(person_id, "ex_partner", opts)
end

defp get_relationship_partners(person_id, type, opts) do
  family_id = opts[:family_id]

  as_a =
    from(r in Relationship,
      join: p in Person,
      on: p.id == r.person_b_id,
      where: r.person_a_id == ^person_id and r.type == ^type,
      select: {p, r}
    )

  as_b =
    from(r in Relationship,
      join: p in Person,
      on: p.id == r.person_a_id,
      where: r.person_b_id == ^person_id and r.type == ^type,
      select: {p, r}
    )

  as_a = maybe_filter_by_family(as_a, :person_b_id, family_id)
  as_b = maybe_filter_by_family(as_b, :person_b_id, family_id)

  Repo.all(as_a) ++ Repo.all(as_b)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "feat: add family_id filtering to get_partners/2 and get_ex_partners/2"
```

---

### Task 4: Add family_id filtering to Relationships.get_children_of_pair/3 and get_solo_children/2

**Files:**
- Modify: `lib/ancestry/relationships.ex:172-198` (get_children_of_pair, get_solo_children)
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing tests**

Add to the `describe "get_children_of_pair/2"` block:

```elixir
test "filters children of pair by family_id" do
  family1 = family_fixture(%{name: "Family 1"})
  family2 = family_fixture(%{name: "Family 2"})

  {:ok, father} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
  {:ok, mother} = People.create_person(family1, %{given_name: "Mom", surname: "D"})
  People.add_to_family(father, family2)
  People.add_to_family(mother, family2)
  {:ok, child1} = People.create_person(family1, %{given_name: "Kid1", surname: "D"})
  {:ok, child2} = People.create_person(family2, %{given_name: "Kid2", surname: "D"})

  {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
  {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})

  # Without family_id — returns both
  assert length(Relationships.get_children_of_pair(father.id, mother.id)) == 2

  # With family_id — only returns children in that family
  f1 = Relationships.get_children_of_pair(father.id, mother.id, family_id: family1.id)
  assert length(f1) == 1
  assert hd(f1).id == child1.id
end
```

Add to the `describe "get_solo_children/1"` block:

```elixir
test "filters solo children by family_id" do
  family1 = family_fixture(%{name: "Family 1"})
  family2 = family_fixture(%{name: "Family 2"})

  {:ok, parent} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
  People.add_to_family(parent, family2)
  {:ok, solo1} = People.create_person(family1, %{given_name: "Solo1", surname: "D"})
  {:ok, solo2} = People.create_person(family2, %{given_name: "Solo2", surname: "D"})

  {:ok, _} = Relationships.create_relationship(parent, solo1, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(parent, solo2, "parent", %{role: "father"})

  # Without family_id — returns both
  assert length(Relationships.get_solo_children(parent.id)) == 2

  # With family_id — only returns solo children in that family
  f1 = Relationships.get_solo_children(parent.id, family_id: family1.id)
  assert length(f1) == 1
  assert hd(f1).id == solo1.id
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: FAIL

**Step 3: Write minimal implementation**

Replace `get_children_of_pair/2`:

```elixir
def get_children_of_pair(parent_a_id, parent_b_id, opts \\ []) do
  query =
    from(p in Person,
      join: r1 in Relationship,
      on: r1.person_b_id == p.id and r1.person_a_id == ^parent_a_id and r1.type == "parent",
      join: r2 in Relationship,
      on: r2.person_b_id == p.id and r2.person_a_id == ^parent_b_id and r2.type == "parent",
      order_by: [asc_nulls_last: p.birth_year, asc: p.id],
      select: p
    )

  query = maybe_filter_person_by_family(query, opts[:family_id])

  Repo.all(query)
end
```

Replace `get_solo_children/1`:

```elixir
def get_solo_children(person_id, opts \\ []) do
  query =
    from(p in Person,
      join: r in Relationship,
      on: r.person_b_id == p.id and r.person_a_id == ^person_id and r.type == "parent",
      left_join: r2 in Relationship,
      on: r2.person_b_id == p.id and r2.type == "parent" and r2.person_a_id != ^person_id,
      where: is_nil(r2.id),
      order_by: [asc_nulls_last: p.birth_year, asc: p.id],
      select: p
    )

  query = maybe_filter_person_by_family(query, opts[:family_id])

  Repo.all(query)
end
```

Add a second helper for queries where Person `p` is the first binding:

```elixir
defp maybe_filter_person_by_family(query, nil), do: query

defp maybe_filter_person_by_family(query, family_id) do
  from [p, ...] in query,
    join: fm in FamilyMember,
    on: fm.person_id == p.id and fm.family_id == ^family_id
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs --seed 0`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "feat: add family_id filtering to get_children_of_pair/3 and get_solo_children/2"
```

---

### Task 5: Thread family_id through PersonTree

**Files:**
- Modify: `lib/ancestry/people/person_tree.ex`
- Test: `test/ancestry/people/person_tree_test.exs` (new file)

**Step 1: Write the failing test**

Create `test/ancestry/people/person_tree_test.exs`:

```elixir
defmodule Ancestry.People.PersonTreeTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.PersonTree
  alias Ancestry.Relationships

  describe "build/2 with family_id" do
    test "only includes people from the specified family" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      # Shared person — member of both families
      {:ok, person} = People.create_person(family1, %{given_name: "Shared", surname: "Person"})
      People.add_to_family(person, family2)

      # Family 1 relatives
      {:ok, f1_parent} = People.create_person(family1, %{given_name: "F1Dad", surname: "D"})
      {:ok, f1_child} = People.create_person(family1, %{given_name: "F1Kid", surname: "D"})

      # Family 2 relatives
      {:ok, f2_parent} = People.create_person(family2, %{given_name: "F2Dad", surname: "D"})
      {:ok, f2_child} = People.create_person(family2, %{given_name: "F2Kid", surname: "D"})

      # Create relationships
      {:ok, _} = Relationships.create_relationship(f1_parent, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(f2_parent, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(person, f1_child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(person, f2_child, "parent", %{role: "father"})

      # Build tree scoped to family 1
      tree = PersonTree.build(person, family1.id)

      # Ancestors should only have f1_parent
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == f1_parent.id
      assert tree.ancestors.couple.person_b == nil

      # Descendants (solo_children) should only have f1_child
      assert length(tree.center.solo_children) == 1
      assert hd(tree.center.solo_children).person.id == f1_child.id
    end

    test "build/1 without family_id returns all relatives (backwards compat)" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      tree = PersonTree.build(person)
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == parent.id
    end
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people/person_tree_test.exs --seed 0`
Expected: FAIL — `build/2` with family_id not accepted.

**Step 3: Write minimal implementation**

Update `lib/ancestry/people/person_tree.ex`:

```elixir
defmodule Ancestry.People.PersonTree do
  @moduledoc """
  Builds a person-centered family tree with N generations of ancestors
  above and N generations of descendants below a focus person.
  """

  alias Ancestry.People.Person
  alias Ancestry.Relationships

  @max_depth 3

  defstruct [:focus_person, :ancestors, :center, :descendants, :family_id]

  @doc """
  Builds a person-centered tree from the given focus person.
  Optionally scoped to a family_id to only include family members.
  """
  def build(%Person{} = focus_person, family_id \\ nil) do
    opts = if family_id, do: [family_id: family_id], else: []

    center = build_center(focus_person, opts)
    ancestor_tree = build_ancestor_tree(focus_person.id, 0, opts)

    %__MODULE__{
      focus_person: focus_person,
      ancestors: ancestor_tree,
      center: center,
      family_id: family_id
    }
  end

  # --- Center Row ---

  defp build_center(focus_person, opts) do
    build_family_unit_full(focus_person, 0, opts)
  end

  @doc """
  Builds a full family unit for a person, including partner, ex-partners,
  and children grouped by couple. Recurses for descendant generations.
  """
  def build_family_unit_full(person, depth, opts \\ []) do
    partners = Relationships.get_partners(person.id, opts)
    ex_partners = Relationships.get_ex_partners(person.id, opts)

    # Take the first current partner for the center pair
    {partner, _partner_rel} =
      case partners do
        [{p, rel} | _] -> {p, rel}
        [] -> {nil, nil}
      end

    at_limit = depth + 1 >= @max_depth

    # Children with current partner
    partner_children =
      if partner do
        Relationships.get_children_of_pair(person.id, partner.id, opts)
        |> build_child_units(depth, at_limit, opts)
      else
        []
      end

    # Children with each ex-partner
    ex_partner_groups =
      Enum.map(ex_partners, fn {ex, _rel} ->
        children =
          Relationships.get_children_of_pair(person.id, ex.id, opts)
          |> build_child_units(depth, at_limit, opts)

        %{person: ex, children: children}
      end)

    # Solo children (no co-parent)
    solo_children =
      Relationships.get_solo_children(person.id, opts)
      |> build_child_units(depth, at_limit, opts)

    %{
      focus: person,
      partner: partner,
      ex_partners: ex_partner_groups,
      partner_children: partner_children,
      solo_children: solo_children
    }
  end

  defp build_child_units(_children, depth, _at_limit, _opts) when depth >= @max_depth, do: []

  defp build_child_units(children, depth, at_limit, opts) do
    Enum.map(children, fn child ->
      if at_limit do
        # At the limit — just check if they have more, don't recurse
        has_more = Relationships.get_children(child.id, opts) != []
        partners = Relationships.get_partners(child.id, opts)

        partner =
          case partners do
            [{p, _} | _] -> p
            [] -> nil
          end

        %{person: child, partner: partner, has_more: has_more, children: nil}
      else
        # Recurse to build the full subtree
        unit = build_family_unit_full(child, depth + 1, opts)

        has_children =
          unit.partner_children != [] or unit.solo_children != [] or unit.ex_partners != []

        Map.put(unit, :has_more, false) |> Map.put(:has_children, has_children)
      end
    end)
  end

  # --- Ancestors (recursive tree) ---

  @doc false
  defp build_ancestor_tree(_person_id, depth, _opts) when depth >= @max_depth, do: nil

  defp build_ancestor_tree(person_id, depth, opts) do
    parents = Relationships.get_parents(person_id, opts)

    {person_a, person_b} =
      case parents do
        [] -> {nil, nil}
        [{p, _}] -> {p, nil}
        [{p1, _}, {p2, _} | _] -> {p1, p2}
      end

    if is_nil(person_a) and is_nil(person_b) do
      nil
    else
      parent_trees =
        [person_a, person_b]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn person ->
          case build_ancestor_tree(person.id, depth + 1, opts) do
            nil -> nil
            tree -> %{tree: tree, for_person_id: person.id}
          end
        end)
        |> Enum.reject(&is_nil/1)

      %{
        couple: %{person_a: person_a, person_b: person_b},
        parent_trees: parent_trees
      }
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/people/person_tree_test.exs --seed 0`
Expected: PASS

**Step 5: Run all tests to verify backwards compatibility**

Run: `mix test --seed 0`
Expected: All tests PASS (existing callers use `build/1` which defaults `family_id` to `nil`)

**Step 6: Commit**

```bash
git add lib/ancestry/people/person_tree.ex test/ancestry/people/person_tree_test.exs
git commit -m "feat: thread family_id through PersonTree for family-scoped tree building"
```

---

### Task 6: Wire family_id into FamilyLive.Show

**Files:**
- Modify: `lib/web/live/family_live/show.ex:59-63,230,289-292`

**Step 1: Update all PersonTree.build calls to pass family.id**

In `lib/web/live/family_live/show.ex`, there are 3 places where `PersonTree.build` is called. Update all of them:

1. `handle_params` (line ~61):
```elixir
# Before:
PersonTree.build(focus_person)
# After:
PersonTree.build(focus_person, socket.assigns.family.id)
```

2. `handle_event("link_person", ...)` (line ~230):
```elixir
# Before:
tree = if focus_person, do: PersonTree.build(focus_person), else: nil
# After:
tree = if focus_person, do: PersonTree.build(focus_person, family.id), else: nil
```

3. `handle_info({:relationship_saved, ...})` (line ~289-292):
```elixir
# Before:
PersonTree.build(focus_person)
# After:
PersonTree.build(focus_person, family.id)
```

**Step 2: Run all tests**

Run: `mix test --seed 0`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add lib/web/live/family_live/show.ex
git commit -m "feat: pass family_id to PersonTree.build in FamilyLive.Show"
```

---

### Task 7: Simplify maybe_filter helpers

**Files:**
- Modify: `lib/ancestry/relationships.ex` (the helper functions)

After all the filtering works, review the two helpers (`maybe_filter_by_family` and `maybe_filter_person_by_family`). Since both do the same thing — join on `FamilyMember` filtering by `person_id` — they can likely be consolidated. The difference is just which binding position holds the person.

**Step 1: Review and simplify**

Look at the helpers. If `maybe_filter_by_family` and `maybe_filter_person_by_family` have the same join logic, consolidate into one. The key difference is:
- In `get_parents`/`get_children`: the Person `p` is at binding position `[r, p]`
- In `get_children_of_pair`/`get_solo_children`: the Person `p` is at position `[p, ...]`

If they can't be easily unified, leave as-is — two small helpers is fine.

**Step 2: Run all tests**

Run: `mix test --seed 0`
Expected: All tests PASS

**Step 3: Run precommit**

Run: `mix precommit`
Expected: PASS — no warnings, formatted, all tests pass

**Step 4: Commit**

```bash
git add lib/ancestry/relationships.ex
git commit -m "refactor: simplify family_id filtering helpers in Relationships"
```
