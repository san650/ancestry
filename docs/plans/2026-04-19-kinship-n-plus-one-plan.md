# Kinship N+1 Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all per-node DB queries in both blood kinship and in-law calculations by routing through the in-memory `FamilyGraph`, extract `Kinship.Blood`, rename label modules, and simplify `KinshipLive`.

**Architecture:** `Kinship` becomes a thin orchestrator (blood → in-law fallback) with a shared graph-aware BFS primitive. `Kinship.Blood` (new) and `Kinship.InLaw` (modified) both use `FamilyGraph` lookups instead of DB queries. Two new `FamilyGraph` functions (`all_partners/2`, `partner_relationship/3`) support `InLaw`. Label modules renamed for clarity.

**Tech Stack:** Elixir, Ecto, Phoenix LiveView

**Spec:** `docs/plans/2026-04-19-kinship-n-plus-one.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `lib/ancestry/people/family_graph.ex` | Add `all_partners/2` + `partner_relationship/3` |
| Modify | `test/ancestry/people/family_graph_test.exs` | Tests for new lookups |
| Rename | `lib/ancestry/kinship/label.ex` → `blood_relationship_label.ex` | Module rename `Label` → `BloodRelationshipLabel` |
| Rename | `lib/ancestry/kinship/in_law_label.ex` → `in_law_relationship_label.ex` | Module rename `InLawLabel` → `InLawRelationshipLabel` |
| Rename | `test/ancestry/kinship/label_test.exs` → `blood_relationship_label_test.exs` | Test rename |
| Rename | `test/ancestry/kinship/in_law_label_test.exs` → `in_law_relationship_label_test.exs` | Test rename |
| Create | `lib/ancestry/kinship/blood.ex` | Blood kinship algorithm extracted from `kinship.ex` |
| Modify | `lib/ancestry/kinship.ex` | Slim to orchestrator + shared BFS |
| Modify | `lib/ancestry/kinship/in_law.ex` | Accept `%FamilyGraph{}`, swap all DB calls |
| Modify | `test/ancestry/kinship/in_law_test.exs` | Migrate to `calculate/3` with graph |
| Modify | `lib/web/live/kinship_live.ex` | Simplify `maybe_calculate/1` |
| Modify | `priv/gettext/default.pot` | Update module name in comments |
| Modify | `priv/gettext/en-US/LC_MESSAGES/default.po` | Update module name in comments |
| Modify | `priv/gettext/es-UY/LC_MESSAGES/default.po` | Update module name in comments |

---

## Task 1: Add `FamilyGraph` lookups for InLaw

**Files:**
- Modify: `lib/ancestry/people/family_graph.ex`
- Modify: `test/ancestry/people/family_graph_test.exs`

- [ ] **Step 1: Add `all_partners/2` and `partner_relationship/3` to FamilyGraph**

Add after `fetch_person!/2` in `lib/ancestry/people/family_graph.ex`:

```elixir
  @doc "Returns [{%Person{}, %Relationship{}}] — all partners (active + former)."
  def all_partners(%__MODULE__{} = graph, person_id) do
    Map.get(graph.partners_by_person, person_id, [])
  end

  @doc "Returns %Relationship{} or nil — partner relationship between two people."
  def partner_relationship(%__MODULE__{} = graph, person_a_id, person_b_id) do
    graph.partners_by_person
    |> Map.get(person_a_id, [])
    |> Enum.find_value(fn {p, rel} -> if p.id == person_b_id, do: rel end)
  end
```

- [ ] **Step 2: Add parity tests for new lookups**

Add to `test/ancestry/people/family_graph_test.exs` inside the `"lookup parity with Ancestry.Relationships"` describe block:

```elixir
    test "all_partners returns active + former combined", %{family: family, parent: parent, partner: partner, ex: ex} do
      graph = FamilyGraph.for_family(family.id)

      result = FamilyGraph.all_partners(graph, parent.id)
      result_ids = Enum.map(result, fn {p, _} -> p.id end) |> MapSet.new()

      assert MapSet.member?(result_ids, partner.id)
      assert MapSet.member?(result_ids, ex.id)
    end

    test "all_partners returns empty for person with no partners", %{family: family, child: child} do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.all_partners(graph, child.id) == []
    end

    test "partner_relationship returns relationship between partners", %{family: family, parent: parent, partner: partner} do
      graph = FamilyGraph.for_family(family.id)

      rel = FamilyGraph.partner_relationship(graph, parent.id, partner.id)
      assert rel != nil
      assert rel.type == "married"
    end

    test "partner_relationship returns nil for non-partners", %{family: family, parent: parent, grandpa: grandpa} do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.partner_relationship(graph, parent.id, grandpa.id) == nil
    end

    test "partner_relationship is bidirectional", %{family: family, parent: parent, partner: partner} do
      graph = FamilyGraph.for_family(family.id)

      assert FamilyGraph.partner_relationship(graph, parent.id, partner.id) != nil
      assert FamilyGraph.partner_relationship(graph, partner.id, parent.id) != nil
    end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/ancestry/people/family_graph_test.exs -v`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/people/family_graph.ex test/ancestry/people/family_graph_test.exs
git commit -m "feat: add all_partners/2 and partner_relationship/3 to FamilyGraph

Two new lookups on the existing partners_by_person index, needed
by the InLaw module's migration to in-memory graph traversal."
```

---

## Task 2: Rename Label modules

**Files:**
- Rename: `lib/ancestry/kinship/label.ex` → `lib/ancestry/kinship/blood_relationship_label.ex`
- Rename: `lib/ancestry/kinship/in_law_label.ex` → `lib/ancestry/kinship/in_law_relationship_label.ex`
- Rename: `test/ancestry/kinship/label_test.exs` → `test/ancestry/kinship/blood_relationship_label_test.exs`
- Rename: `test/ancestry/kinship/in_law_label_test.exs` → `test/ancestry/kinship/in_law_relationship_label_test.exs`
- Modify: `lib/ancestry/kinship.ex` (alias)
- Modify: `lib/ancestry/kinship/in_law.ex` (alias + unaliased calls)
- Modify: `priv/gettext/default.pot`, `priv/gettext/en-US/LC_MESSAGES/default.po`, `priv/gettext/es-UY/LC_MESSAGES/default.po`

- [ ] **Step 1: Rename Label → BloodRelationshipLabel (all changes atomic — do NOT compile between sub-steps)**

```bash
git mv lib/ancestry/kinship/label.ex lib/ancestry/kinship/blood_relationship_label.ex
git mv test/ancestry/kinship/label_test.exs test/ancestry/kinship/blood_relationship_label_test.exs
```

In `lib/ancestry/kinship/blood_relationship_label.ex`, change the module name:
```elixir
# old
defmodule Ancestry.Kinship.Label do
# new
defmodule Ancestry.Kinship.BloodRelationshipLabel do
```

In `test/ancestry/kinship/blood_relationship_label_test.exs`, change:
```elixir
# old
defmodule Ancestry.Kinship.LabelTest do
  # ...
  alias Ancestry.Kinship.Label
# new
defmodule Ancestry.Kinship.BloodRelationshipLabelTest do
  # ...
  alias Ancestry.Kinship.BloodRelationshipLabel, as: Label
```

Keep the alias `as: Label` so all test assertions (`Label.format(...)`) stay unchanged.

In `lib/ancestry/kinship.ex`, update the alias:
```elixir
# old
  alias Ancestry.Kinship.Label
# new
  alias Ancestry.Kinship.BloodRelationshipLabel, as: Label
```

**Also in this step** — update the three unaliased calls in `lib/ancestry/kinship/in_law.ex` at lines 235, 242, 243 (must be done atomically with the module rename to avoid compilation failure):
```elixir
# old (lines 235, 242, 243)
    Ancestry.Kinship.Label.format(...)
# new
    Ancestry.Kinship.BloodRelationshipLabel.format(...)
```

- [ ] **Step 2: Rename InLawLabel → InLawRelationshipLabel (all changes atomic)**

```bash
git mv lib/ancestry/kinship/in_law_label.ex lib/ancestry/kinship/in_law_relationship_label.ex
git mv test/ancestry/kinship/in_law_label_test.exs test/ancestry/kinship/in_law_relationship_label_test.exs
```

In `lib/ancestry/kinship/in_law_relationship_label.ex`, change:
```elixir
# old
defmodule Ancestry.Kinship.InLawLabel do
# new
defmodule Ancestry.Kinship.InLawRelationshipLabel do
```

In `test/ancestry/kinship/in_law_relationship_label_test.exs`, change:
```elixir
# old
defmodule Ancestry.Kinship.InLawLabelTest do
  # ...
  alias Ancestry.Kinship.InLawLabel
# new
defmodule Ancestry.Kinship.InLawRelationshipLabelTest do
  # ...
  alias Ancestry.Kinship.InLawRelationshipLabel, as: InLawLabel
```

In `lib/ancestry/kinship/in_law.ex`, update the alias:
```elixir
# old
  alias Ancestry.Kinship.InLawLabel
# new
  alias Ancestry.Kinship.InLawRelationshipLabel, as: InLawLabel
```

- [ ] **Step 3: Update gettext comments**

In `priv/gettext/default.pot` and `priv/gettext/es-UY/LC_MESSAGES/default.po`:
- Replace `Ancestry.Kinship.Label` with `Ancestry.Kinship.BloodRelationshipLabel`
- Replace `Ancestry.Kinship.InLawLabel` with `Ancestry.Kinship.InLawRelationshipLabel`

In `priv/gettext/en-US/LC_MESSAGES/default.po`:
- Replace `Ancestry.Kinship.Label` with `Ancestry.Kinship.BloodRelationshipLabel`
- Replace `Ancestry.Kinship.InLawLabel` with `Ancestry.Kinship.InLawRelationshipLabel`

- [ ] **Step 4: Run tests**

Run: `mix test test/ancestry/kinship/ -v`
Expected: all label tests + in_law tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: rename Label → BloodRelationshipLabel, InLawLabel → InLawRelationshipLabel

Consistent naming that parallels Blood / InLaw module structure.
All aliases, test modules, unaliased references, and gettext
comments updated."
```

---

## Task 3: Extract `Kinship.Blood` + delegate from `Kinship.calculate/3`

**Files:**
- Create: `lib/ancestry/kinship/blood.ex`
- Modify: `lib/ancestry/kinship.ex`

**Key constraint:** `kinship_test.exs` already calls `Kinship.calculate/3` with `%FamilyGraph{}`. After this task, `calculate/3` exists and those tests pass. `KinshipLive` still handles the in-law fallback inline — the orchestrator fallback comes in Task 5.

- [ ] **Step 1: Create `lib/ancestry/kinship/blood.ex`**

```elixir
defmodule Ancestry.Kinship.Blood do
  @moduledoc """
  Blood kinship algorithm: bidirectional BFS to find the MRCA,
  classify the relationship, and build the path.
  """

  alias Ancestry.Kinship
  alias Ancestry.Kinship.BloodRelationshipLabel
  alias Ancestry.People.FamilyGraph

  @doc """
  Calculates the blood kinship relationship between two people.

  Returns `{:ok, %Kinship{}}` or `{:error, :no_common_ancestor}`.
  """
  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    ancestors_a = Kinship.build_ancestor_map(person_a_id, graph)
    ancestors_b = Kinship.build_ancestor_map(person_b_id, graph)

    common_ancestor_ids =
      ancestors_a
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(ancestors_b)))

    if MapSet.size(common_ancestor_ids) == 0 do
      {:error, :no_common_ancestor}
    else
      {mrca_id, steps_a, steps_b, path_a, path_b} =
        common_ancestor_ids
        |> Enum.map(fn id ->
          {depth_a, pa} = Map.fetch!(ancestors_a, id)
          {depth_b, pb} = Map.fetch!(ancestors_b, id)
          {id, depth_a, depth_b, pa, pb}
        end)
        |> Enum.min_by(fn {_id, da, db, _pa, _pb} -> da + db end)

      person_a = FamilyGraph.fetch_person!(graph, person_a_id)
      mrca = FamilyGraph.fetch_person!(graph, mrca_id)
      half? = half_relationship?(mrca_id, steps_a, steps_b, ancestors_a, ancestors_b)
      relationship = BloodRelationshipLabel.format(steps_a, steps_b, half?, person_a.gender)
      path = build_path(path_a, path_b, steps_a, steps_b, graph)
      dna_pct = Kinship.dna_percentage(steps_a, steps_b, half?)

      {:ok,
       %Kinship{
         relationship: relationship,
         steps_a: steps_a,
         steps_b: steps_b,
         path: path,
         mrca: mrca,
         half?: half?,
         dna_percentage: dna_pct
       }}
    end
  end

  # Determine if the relationship is a half-relationship.
  defp half_relationship?(_mrca_id, steps_a, steps_b, _ancestors_a, _ancestors_b)
       when steps_a == 0 or steps_b == 0 do
    false
  end

  defp half_relationship?(_mrca_id, steps_a, steps_b, ancestors_a, ancestors_b) do
    common_at_mrca_depth =
      ancestors_a
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(ancestors_b)))
      |> Enum.count(fn id ->
        {da, _} = Map.fetch!(ancestors_a, id)
        {db, _} = Map.fetch!(ancestors_b, id)
        da == steps_a and db == steps_b
      end)

    common_at_mrca_depth < 2
  end

  # Build the full path from person A through MRCA down to person B.
  defp build_path(path_a, path_b, steps_a, steps_b, graph) do
    path_b_descending =
      path_b
      |> Enum.reverse()
      |> tl()

    full_ids = path_a ++ path_b_descending

    full_ids
    |> Enum.with_index()
    |> Enum.map(fn {id, index} ->
      person = FamilyGraph.fetch_person!(graph, id)
      label = path_label(index, steps_a, steps_b, person.gender)
      %{person: person, label: label}
    end)
  end

  defp path_label(0, _steps_a, _steps_b, _gender), do: "-"

  defp path_label(index, steps_a, _steps_b, gender) when index <= steps_a do
    BloodRelationshipLabel.format(0, index, false, gender)
  end

  defp path_label(index, steps_a, _steps_b, gender) do
    down_steps = index - steps_a

    cond do
      steps_a == 0 ->
        BloodRelationshipLabel.format(down_steps, 0, false, gender)

      true ->
        BloodRelationshipLabel.format(down_steps, steps_a, false, gender)
    end
  end
end
```

- [ ] **Step 2: Rewrite `lib/ancestry/kinship.ex` — delegate calculate/3, add graph-aware BFS**

Replace the entire content of `lib/ancestry/kinship.ex`:

```elixir
defmodule Ancestry.Kinship do
  @moduledoc """
  Orchestrates kinship calculations: tries blood kinship first,
  falls back to in-law detection. Owns shared primitives (BFS, DNA%).
  """

  alias Ancestry.Kinship.Blood
  alias Ancestry.People.FamilyGraph

  @max_depth 10

  defstruct [:relationship, :steps_a, :steps_b, :path, :mrca, :half?, :dna_percentage]

  @doc """
  Calculates the approximate percentage of shared DNA between two people
  based on their generational distances from the Most Recent Common Ancestor.
  """
  def dna_percentage(steps_a, steps_b, half?) do
    base =
      cond do
        steps_a == 0 or steps_b == 0 ->
          100.0 / :math.pow(2, max(steps_a, steps_b))

        steps_a == 1 and steps_b == 1 ->
          50.0

        true ->
          100.0 / :math.pow(2, steps_a + steps_b - 1)
      end

    if half?, do: base / 2, else: base
  end

  @doc """
  Calculates the kinship relationship between two people using a pre-built graph.

  Returns `{:ok, %Kinship{}}` for blood relatives,
  `{:error, :same_person}` if the IDs match,
  or `{:error, :no_common_ancestor}` if BFS exhausts max depth.

  Note: The orchestrator fallback to InLaw will be added in a later commit.
  Currently delegates directly to Blood.calculate/3.
  """
  def calculate(person_a_id, person_b_id, _graph) when person_a_id == person_b_id do
    {:error, :same_person}
  end

  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    Blood.calculate(person_a_id, person_b_id, graph)
  end

  @doc """
  Build an ancestor map using graph-aware BFS.
  Returns %{person_id => {depth, path_from_start}}.
  """
  def build_ancestor_map(person_id, %FamilyGraph{} = graph) do
    initial = %{person_id => {0, [person_id]}}
    bfs_expand([person_id], initial, 1, graph)
  end

  defp bfs_expand(_frontier, ancestors, depth, _graph) when depth > @max_depth,
    do: ancestors

  defp bfs_expand([], ancestors, _depth, _graph), do: ancestors

  defp bfs_expand(frontier, ancestors, depth, graph) do
    next_frontier =
      frontier
      |> Enum.flat_map(fn person_id ->
        FamilyGraph.parents(graph, person_id)
        |> Enum.map(fn {parent, _rel} -> {parent.id, person_id} end)
      end)
      |> Enum.reject(fn {parent_id, _child_id} -> Map.has_key?(ancestors, parent_id) end)

    new_ancestors =
      Enum.reduce(next_frontier, ancestors, fn {parent_id, child_id}, acc ->
        {_child_depth, child_path} = Map.fetch!(acc, child_id)
        Map.put(acc, parent_id, {depth, child_path ++ [parent_id]})
      end)

    new_frontier_ids =
      next_frontier
      |> Enum.map(fn {parent_id, _} -> parent_id end)
      |> Enum.uniq()

    bfs_expand(new_frontier_ids, new_ancestors, depth + 1, graph)
  end

  # --- Temporary: keep old DB-based BFS for InLaw until Task 4 migrates it ---

  alias Ancestry.Relationships

  @doc """
  Build an ancestor map using DB queries (legacy — will be removed after InLaw migration).
  """
  def build_ancestor_map(person_id) do
    initial = %{person_id => {0, [person_id]}}
    legacy_bfs_expand([person_id], initial, 1)
  end

  defp legacy_bfs_expand(_frontier, ancestors, depth) when depth > @max_depth, do: ancestors
  defp legacy_bfs_expand([], ancestors, _depth), do: ancestors

  defp legacy_bfs_expand(frontier, ancestors, depth) do
    next_frontier =
      frontier
      |> Enum.flat_map(fn person_id ->
        Relationships.get_parents(person_id)
        |> Enum.map(fn {parent, _rel} -> {parent.id, person_id} end)
      end)
      |> Enum.reject(fn {parent_id, _child_id} -> Map.has_key?(ancestors, parent_id) end)

    new_ancestors =
      Enum.reduce(next_frontier, ancestors, fn {parent_id, child_id}, acc ->
        {_child_depth, child_path} = Map.fetch!(acc, child_id)
        Map.put(acc, parent_id, {depth, child_path ++ [parent_id]})
      end)

    new_frontier_ids =
      next_frontier
      |> Enum.map(fn {parent_id, _} -> parent_id end)
      |> Enum.uniq()

    legacy_bfs_expand(new_frontier_ids, new_ancestors, depth + 1)
  end
end
```

- [ ] **Step 3: Run kinship tests**

Run: `mix test test/ancestry/kinship_test.exs -v`
Expected: all 25+ tests pass. These already call `Kinship.calculate/3` with `%FamilyGraph{}`.

- [ ] **Step 4: Run full test suite**

Run: `mix test`
Expected: all green. InLaw tests still pass (they call `InLaw.calculate/2` which calls `Kinship.build_ancestor_map/1` — the legacy arity we kept).

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship/blood.ex lib/ancestry/kinship.ex
git commit -m "refactor: extract Kinship.Blood, add Kinship.calculate/3

Blood kinship algorithm extracted to Kinship.Blood. Kinship.calculate/3
delegates to Blood.calculate/3 using FamilyGraph lookups (0 DB queries).
Graph-aware build_ancestor_map/2 added as shared BFS primitive. Legacy
DB-based build_ancestor_map/1 kept temporarily for InLaw."
```

---

## Task 4: Migrate `InLaw` to `calculate/3` with `FamilyGraph`

**Files:**
- Modify: `lib/ancestry/kinship/in_law.ex`
- Modify: `test/ancestry/kinship/in_law_test.exs`
- Modify: `lib/ancestry/kinship.ex` (remove legacy BFS)

- [ ] **Step 1: Rewrite `lib/ancestry/kinship/in_law.ex` to accept `%FamilyGraph{}`**

Replace the entire content:

```elixir
defmodule Ancestry.Kinship.InLaw do
  @moduledoc """
  Detects in-law relationships by partner-hopping when blood BFS finds no MRCA.

  Algorithm:
  1. Check if A and B are direct partners (spouse check).
  2. For each of A's partners, run blood BFS between that partner and B.
  3. For each of B's partners, run blood BFS between A and that partner.
  4. Pick the best result (lowest total steps; tiebreak: active partner type wins).
  5. Build the path and label.
  """

  alias Ancestry.Kinship
  alias Ancestry.Kinship.InLawRelationshipLabel, as: InLawLabel
  alias Ancestry.People.FamilyGraph
  alias Ancestry.Relationships.Relationship

  defstruct [:relationship, :partner_link, :path, :steps_a]

  @doc """
  Calculates an in-law relationship between two people using a pre-built graph.

  Returns `{:ok, %InLaw{}}` or `{:error, :no_relationship}`.
  """
  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    person_a = FamilyGraph.fetch_person!(graph, person_a_id)
    person_b = FamilyGraph.fetch_person!(graph, person_b_id)

    with {:error, :no_spouse} <- check_direct_spouse(person_a, person_b, graph) do
      find_via_partner_hop(person_a, person_b, graph)
    end
  end

  # --- Step 1: Direct spouse check ---

  defp check_direct_spouse(person_a, person_b, graph) do
    case FamilyGraph.partner_relationship(graph, person_a.id, person_b.id) do
      nil ->
        {:error, :no_spouse}

      _rel ->
        relationship = InLawLabel.format(:spouse, :spouse, person_a.gender)

        path = [
          %{person: person_a, label: "-", partner_link?: false},
          %{person: person_b, label: "-", partner_link?: false}
        ]

        {:ok,
         %__MODULE__{
           relationship: relationship,
           partner_link: nil,
           path: path,
           steps_a: 0
         }}
    end
  end

  # --- Steps 2-5: Partner-hop BFS ---

  defp find_via_partner_hop(person_a, person_b, graph) do
    a_side_results = hop_a_side(person_a, person_b, graph)
    b_side_results = hop_b_side(person_a, person_b, graph)

    all_results = a_side_results ++ b_side_results

    case pick_best(all_results) do
      nil ->
        {:error, :no_relationship}

      {steps_a, steps_b, path_ids, partner_person, side, _rel} ->
        relationship = InLawLabel.format(steps_a, steps_b, person_a.gender)

        path =
          build_in_law_path(
            path_ids,
            person_a,
            person_b,
            partner_person,
            side,
            steps_a,
            steps_b,
            graph
          )

        {:ok,
         %__MODULE__{
           relationship: relationship,
           partner_link: %{person: partner_person, side: side},
           path: path,
           steps_a: steps_a
         }}
    end
  end

  # Hop through A's partners: BFS between each partner and B
  defp hop_a_side(person_a, person_b, graph) do
    partners_of_a = FamilyGraph.all_partners(graph, person_a.id)
    ancestors_b = Kinship.build_ancestor_map(person_b.id, graph)

    Enum.flat_map(partners_of_a, fn {partner, rel} ->
      ancestors_partner = Kinship.build_ancestor_map(partner.id, graph)

      case find_mrca(ancestors_partner, ancestors_b) do
        nil ->
          []

        {steps_a, steps_b, path_partner, path_b} ->
          path_ids = {person_a.id, path_partner, path_b}
          [{steps_a, steps_b, path_ids, partner, :a, rel}]
      end
    end)
  end

  # Hop through B's partners: BFS between A and each partner
  defp hop_b_side(person_a, person_b, graph) do
    partners_of_b = FamilyGraph.all_partners(graph, person_b.id)
    ancestors_a = Kinship.build_ancestor_map(person_a.id, graph)

    Enum.flat_map(partners_of_b, fn {partner, rel} ->
      ancestors_partner = Kinship.build_ancestor_map(partner.id, graph)

      case find_mrca(ancestors_a, ancestors_partner) do
        nil ->
          []

        {steps_a, steps_b, path_a, path_partner} ->
          path_ids = {path_a, path_partner, person_b.id}
          [{steps_a, steps_b, path_ids, partner, :b, rel}]
      end
    end)
  end

  # Find the MRCA between two ancestor maps.
  defp find_mrca(ancestors_a, ancestors_b) do
    common_ancestor_ids =
      ancestors_a
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(ancestors_b)))

    if MapSet.size(common_ancestor_ids) == 0 do
      nil
    else
      {_mrca_id, steps_a, steps_b, path_a, path_b} =
        common_ancestor_ids
        |> Enum.map(fn id ->
          {da, pa} = Map.fetch!(ancestors_a, id)
          {db, pb} = Map.fetch!(ancestors_b, id)
          {id, da, db, pa, pb}
        end)
        |> Enum.min_by(fn {_id, da, db, _pa, _pb} -> da + db end)

      {steps_a, steps_b, path_a, path_b}
    end
  end

  # Pick the best candidate: lowest steps_a + steps_b, tiebreak: active > former
  defp pick_best([]), do: nil

  defp pick_best(candidates) do
    Enum.min_by(candidates, fn {steps_a, steps_b, _path_ids, _partner, _side, rel} ->
      total = steps_a + steps_b
      type_score = if Relationship.active_partner_type?(rel.type), do: 0, else: 1
      {total, type_score}
    end)
  end

  defp build_in_law_path(path_ids, person_a, person_b, _partner_person, side, steps_a, steps_b, graph) do
    case side do
      :b ->
        {path_a, path_partner, _b_id} = path_ids
        blood_ids = merge_blood_path(path_a, path_partner)

        blood_nodes =
          blood_ids
          |> Enum.with_index()
          |> Enum.map(fn {id, index} ->
            person = FamilyGraph.fetch_person!(graph, id)
            label = blood_path_label(index, steps_a, steps_b, person.gender)
            is_last = index == length(blood_ids) - 1
            %{person: person, label: label, partner_link?: is_last}
          end)

        b_label = InLawLabel.format(steps_b, steps_a, person_b.gender)

        blood_nodes ++
          [%{person: person_b, label: b_label, partner_link?: true}]

      :a ->
        {_a_id, path_partner, path_b} = path_ids
        blood_ids = merge_blood_path(path_partner, path_b)

        blood_nodes =
          blood_ids
          |> Enum.with_index()
          |> Enum.map(fn {id, index} ->
            person = FamilyGraph.fetch_person!(graph, id)
            label = blood_path_label(index, steps_a, steps_b, person.gender)
            %{person: person, label: label, partner_link?: index == 0}
          end)

        [%{person: person_a, label: "-", partner_link?: true} | blood_nodes]
    end
  end

  defp blood_path_label(0, _steps_a, _steps_b, _gender), do: "-"

  defp blood_path_label(index, steps_a, _steps_b, gender) when index <= steps_a do
    Ancestry.Kinship.BloodRelationshipLabel.format(0, index, false, gender)
  end

  defp blood_path_label(index, steps_a, _steps_b, gender) do
    down_steps = index - steps_a

    cond do
      steps_a == 0 -> Ancestry.Kinship.BloodRelationshipLabel.format(down_steps, 0, false, gender)
      true -> Ancestry.Kinship.BloodRelationshipLabel.format(down_steps, steps_a, false, gender)
    end
  end

  defp merge_blood_path(path_ascending, path_descending) do
    descending_tail =
      path_descending
      |> Enum.reverse()
      |> tl()

    path_ascending ++ descending_tail
  end
end
```

- [ ] **Step 2: Update `test/ancestry/kinship/in_law_test.exs`**

Changes needed:
1. Add alias for `FamilyGraph`
2. In every test, build a graph and pass it to `InLaw.calculate/3`
3. Rename describe blocks from `"calculate/2"` to `"calculate/3"`

```elixir
# At top, add alias:
  alias Ancestry.People.FamilyGraph

# In EVERY test that calls InLaw.calculate, change from:
      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id)
# To:
      graph = FamilyGraph.for_family(family.id)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id, graph)

# Rename all describe blocks:
  describe "calculate/2 - direct spouse" do  →  describe "calculate/3 - direct spouse" do
  describe "calculate/2 - parent-in-law" do  →  describe "calculate/3 - parent-in-law" do
  describe "calculate/2 - sibling-in-law" do  →  describe "calculate/3 - sibling-in-law" do
  describe "calculate/2 - extended in-law" do  →  describe "calculate/3 - extended in-law" do
  describe "calculate/2 - tiebreaker: active partner wins" do  →  describe "calculate/3 - tiebreaker" do
  describe "calculate/2 - no relationship" do  →  describe "calculate/3 - no relationship" do
  describe "calculate/2 - path structure" do  →  describe "calculate/3 - path structure" do
```

**Important:** The graph must be built **after** all fixtures (persons, relationships) are created — otherwise the graph won't contain the just-created data. In each test body, insert `graph = FamilyGraph.for_family(family.id)` as the last line before the `InLaw.calculate` call. The `family` variable is already bound from `family_fixture()` at the start of each test.

- [ ] **Step 2b: Add query-count assertion test**

Add a new describe block to `test/ancestry/kinship/in_law_test.exs`:

```elixir
  describe "calculate/3 - zero DB queries with pre-built graph" do
    test "emits 0 queries when graph is pre-built" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      graph = FamilyGraph.for_family(family.id)

      ref = :telemetry.attach("in-law-query-count", [:ancestry, :repo, :query], fn _, _, _, _ ->
        send(self(), :query_fired)
      end, nil)

      _result = InLaw.calculate(father.id, wife.id, graph)

      :telemetry.detach("in-law-query-count")

      refute_received :query_fired, "Expected 0 queries but at least one was emitted"
    end
  end
```

- [ ] **Step 2c: Add family-scoping test for in-law**

Add a new describe block to `test/ancestry/kinship/in_law_test.exs`:

```elixir
  describe "calculate/3 - family scoping" do
    test "returns :no_relationship when partner hop crosses family boundary" do
      family = family_fixture()
      org = Ancestry.Organizations.get_organization!(family.organization_id)
      {:ok, other_family} = Ancestry.Families.create_family(org, %{name: "Other"})

      person_a = person_fixture(family, %{given_name: "A", surname: "S", gender: "male"})
      partner_of_a = person_fixture(family, %{given_name: "PartnerA", surname: "S", gender: "female"})
      make_partner!(person_a, partner_of_a)

      # Parent of partner is in other_family only — not in family
      parent = person_fixture(other_family, %{given_name: "Parent", surname: "S", gender: "male"})
      person_b = person_fixture(other_family, %{given_name: "B", surname: "S", gender: "male"})
      {:ok, _} = Ancestry.Relationships.create_relationship(parent, partner_of_a, "parent", %{role: "father"})
      {:ok, _} = Ancestry.Relationships.create_relationship(parent, person_b, "parent", %{role: "father"})

      # Add person_b to family so they appear in selectors
      People.add_to_family(person_b, family)

      graph = FamilyGraph.for_family(family.id)

      # Parent is outside the family — partner hop can't find a path
      assert {:error, :no_relationship} = InLaw.calculate(person_a.id, person_b.id, graph)
    end
  end
```

- [ ] **Step 3: Remove legacy BFS from `lib/ancestry/kinship.ex`**

Delete the entire "Temporary: keep old DB-based BFS" section from `kinship.ex`:
- Remove `alias Ancestry.Relationships`
- Remove `build_ancestor_map/1` (the old 1-arity)
- Remove `legacy_bfs_expand/3` and all its clauses

- [ ] **Step 4: Run in-law tests**

Run: `mix test test/ancestry/kinship/in_law_test.exs -v`
Expected: all tests pass.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/kinship/in_law.ex test/ancestry/kinship/in_law_test.exs lib/ancestry/kinship.ex
git commit -m "perf: migrate InLaw to FamilyGraph — 0 DB queries after graph load

InLaw.calculate/3 takes a %FamilyGraph{}. All DB calls replaced
with graph lookups. Legacy build_ancestor_map/1 removed from Kinship.
Every in-law calculation is now pure in-memory."
```

---

## Task 5: Wire orchestrator fallback + simplify `KinshipLive`

**Files:**
- Modify: `lib/ancestry/kinship.ex`
- Modify: `lib/web/live/kinship_live.ex`

- [ ] **Step 1: Add blood → in-law fallback to `Kinship.calculate/3`**

In `lib/ancestry/kinship.ex`, update `calculate/3`:

```elixir
  # old
  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    Blood.calculate(person_a_id, person_b_id, graph)
  end

  # new
  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    case Blood.calculate(person_a_id, person_b_id, graph) do
      {:ok, _} = result ->
        result

      {:error, :no_common_ancestor} ->
        case InLaw.calculate(person_a_id, person_b_id, graph) do
          {:ok, _} = result -> result
          {:error, _} -> {:error, :no_relationship}
        end
    end
  end
```

Add alias at the top of the module:

```elixir
  alias Ancestry.Kinship.InLaw
```

Also update the `@moduledoc` and `@doc` on `calculate/3` to reflect the orchestrator behavior:

```elixir
  @doc """
  Calculates the kinship relationship between two people using a pre-built graph.

  Tries blood kinship first. If no common ancestor is found, falls back to
  in-law detection via partner-hop BFS.

  Returns `{:ok, %Kinship{}}` for blood relatives,
  `{:ok, %InLaw{}}` for in-law relatives,
  `{:error, :same_person}` if the IDs match,
  or `{:error, :no_relationship}` if neither path finds a connection.
  """
```

- [ ] **Step 2: Simplify `KinshipLive.maybe_calculate/1`**

In `lib/web/live/kinship_live.ex`, replace `maybe_calculate/1` (lines 188-248):

```elixir
  defp maybe_calculate(socket) do
    case {socket.assigns.person_a, socket.assigns.person_b} do
      {%Person{id: a_id}, %Person{id: b_id}} ->
        case Kinship.calculate(a_id, b_id, socket.assigns.family_graph) do
          {:ok, result} ->
            path_a = Enum.slice(result.path, 0, result.steps_a + 1) |> Enum.reverse()
            path_b = Enum.slice(result.path, result.steps_a, length(result.path) - result.steps_a)

            socket
            |> assign(:result, {:ok, result})
            |> assign(:path_a, path_a)
            |> assign(:path_b, path_b)

          error ->
            socket
            |> assign(:result, error)
            |> assign(:path_a, [])
            |> assign(:path_b, [])
        end

      _ ->
        assign(socket, result: nil, path_a: [], path_b: [])
    end
  end
```

Also remove the unused `InLaw` alias from the top of `kinship_live.ex`:

```elixir
# Remove this line:
  alias Ancestry.Kinship.InLaw
```

- [ ] **Step 3: Run kinship + in-law tests + E2E**

Run: `mix test test/ancestry/kinship_test.exs test/ancestry/kinship/in_law_test.exs test/user_flows/calculating_kinship_test.exs -v`
Expected: all pass. The E2E test verifies the template still renders correctly for both blood and in-law results after the `maybe_calculate` simplification (template pattern matches on `%Ancestry.Kinship.InLaw{}` vs `%Ancestry.Kinship{}` — both struct names are unchanged).

- [ ] **Step 4: Run full test suite**

Run: `mix test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/kinship.ex lib/web/live/kinship_live.ex
git commit -m "perf: wire Kinship orchestrator fallback, simplify KinshipLive

Kinship.calculate/3 now tries blood kinship first, falls back to
in-law detection. KinshipLive.maybe_calculate/1 simplified from
~60 lines to ~20 — no longer orchestrates the fallback inline."
```

---

## Task 6: Final verification

- [ ] **Step 1: Run `mix precommit`**

Run: `mix precommit`
Expected: compile (warnings-as-errors), unused deps check, format, and all tests pass.

- [ ] **Step 2: Verify no unused aliases or dead code**

Run: `mix compile --warnings-as-errors 2>&1 | head -20`
Expected: no warnings. Specifically verify:
- No reference to old `Ancestry.Kinship.Label` module
- No reference to old `Ancestry.Kinship.InLawLabel` module
- No reference to `Kinship.calculate/2` or `InLaw.calculate/2`
- No reference to `Kinship.build_ancestor_map/1`
