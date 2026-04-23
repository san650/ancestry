defmodule Ancestry.People.PersonGraphTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.PersonGraph

  alias Ancestry.Relationships

  # ── Helpers ──────────────────────────────────────────────────────────

  defp family_fixture(attrs \\ %{}) do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end

  defp person_nodes(graph) do
    Enum.filter(graph.nodes, &(&1.type == :person))
  end

  defp focus_node(graph) do
    Enum.find(graph.nodes, &(&1.focus == true))
  end

  defp find_person_node(graph, person_id) do
    Enum.find(person_nodes(graph), &(&1.person.id == person_id and not &1.duplicated))
  end

  defp dup_count(graph) do
    Enum.count(person_nodes(graph), & &1.duplicated)
  end

  defp person_ids(graph) do
    person_nodes(graph)
    |> Enum.reject(& &1.duplicated)
    |> Enum.map(& &1.person.id)
    |> MapSet.new()
  end

  defp parent_child_edges(graph) do
    Enum.filter(graph.edges, &(&1.type == :parent_child))
  end

  defp couple_edges(graph) do
    Enum.filter(graph.edges, &(&1.type in [:current_partner, :previous_partner]))
  end

  # ── build/2 with family_id ──────────────────────────────────────────

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

      # Build graph scoped to family 1
      graph = PersonGraph.build(person, family1.id)

      ids = person_ids(graph)

      # Should include person, f1_parent, and f1_child
      assert MapSet.member?(ids, person.id)
      assert MapSet.member?(ids, f1_parent.id)
      assert MapSet.member?(ids, f1_child.id)

      # Should NOT include f2_parent or f2_child
      refute MapSet.member?(ids, f2_parent.id)
      refute MapSet.member?(ids, f2_child.id)
    end

    test "build/2 accepts a pre-built FamilyGraph" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      graph_data = FamilyGraph.for_family(family.id)
      graph = PersonGraph.build(person, graph_data)

      assert find_person_node(graph, parent.id) != nil
      assert find_person_node(graph, person.id) != nil
    end
  end

  # ── Multiple current partners ───────────────────────────────────────

  describe "multiple current partners (widowed and remarried)" do
    test "latest partner by marriage year is placed, both partners visible" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, first_wife} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", deceased: true})

      {:ok, second_wife} =
        People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      # First marriage (1985)
      {:ok, _} =
        Relationships.create_relationship(person, first_wife, "married", %{marriage_year: 1985})

      # Second marriage (1995)
      {:ok, _} =
        Relationships.create_relationship(person, second_wife, "married", %{marriage_year: 1995})

      # Child with first wife
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "Doe"})
      {:ok, _} = Relationships.create_relationship(person, child1, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(first_wife, child1, "parent", %{role: "mother"})

      # Child with second wife
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "Doe"})
      {:ok, _} = Relationships.create_relationship(person, child2, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(second_wife, child2, "parent", %{role: "mother"})

      graph = PersonGraph.build(person, family.id)

      # Both wives should be in the graph
      assert find_person_node(graph, first_wife.id) != nil
      assert find_person_node(graph, second_wife.id) != nil

      # Both children should be in the graph
      assert find_person_node(graph, child1.id) != nil
      assert find_person_node(graph, child2.id) != nil

      # Should have couple edges for both relationships
      assert length(couple_edges(graph)) >= 2
    end

    test "single partner produces couple edge" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, wife} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      {:ok, _} = Relationships.create_relationship(person, wife, "married", %{})

      graph = PersonGraph.build(person, family.id)

      assert find_person_node(graph, wife.id) != nil
      assert length(couple_edges(graph)) == 1
    end

    test "no partners produces no couple edges" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      graph = PersonGraph.build(person, family.id)

      assert couple_edges(graph) == []
      # Only the focus person
      assert length(person_nodes(graph)) == 1
    end
  end

  # ── Current partner selection ────────────────────────────────────────

  describe "current partner selection" do
    test "relationship type partner is selected as current over married partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, wife} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      {:ok, girlfriend} =
        People.create_person(family, %{given_name: "Sarah", surname: "Smith"})

      {:ok, _} =
        Relationships.create_relationship(person, wife, "married", %{marriage_year: 2000})

      {:ok, _} =
        Relationships.create_relationship(person, girlfriend, "relationship", %{})

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      # Both should be in the graph
      assert find_person_node(graph, wife.id) != nil
      assert find_person_node(graph, girlfriend.id) != nil

      # The girlfriend (relationship type) should be the current partner
      # and appear AFTER the person in the row
      focus = focus_node(graph)
      row_nodes = person_nodes(graph) |> Enum.filter(&(&1.row == focus.row))
      sorted = Enum.sort_by(row_nodes, & &1.col)
      ids_in_order = Enum.map(sorted, & &1.person.id)

      person_idx = Enum.find_index(ids_in_order, &(&1 == person.id))
      girlfriend_idx = Enum.find_index(ids_in_order, &(&1 == girlfriend.id))

      assert girlfriend_idx > person_idx,
             "Relationship-type partner should be the current partner (after the person)"
    end

    test "latest marriage_year married partner is selected as current when multiple married" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, first_wife} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      {:ok, second_wife} =
        People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      {:ok, _} =
        Relationships.create_relationship(person, first_wife, "married", %{marriage_year: 1985})

      {:ok, _} =
        Relationships.create_relationship(person, second_wife, "married", %{marriage_year: 1995})

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      # Both should be in the graph
      assert find_person_node(graph, first_wife.id) != nil
      assert find_person_node(graph, second_wife.id) != nil

      # Second wife (latest marriage_year) should be after person (current),
      # first wife should be before person (previous)
      focus = focus_node(graph)
      row_nodes = person_nodes(graph) |> Enum.filter(&(&1.row == focus.row))
      sorted = Enum.sort_by(row_nodes, & &1.col)
      ids_in_order = Enum.map(sorted, & &1.person.id)

      person_idx = Enum.find_index(ids_in_order, &(&1 == person.id))
      first_idx = Enum.find_index(ids_in_order, &(&1 == first_wife.id))
      second_idx = Enum.find_index(ids_in_order, &(&1 == second_wife.id))

      assert second_idx > person_idx,
             "Latest married partner should appear after the person (current)"

      assert first_idx < person_idx,
             "Earlier married partner should appear before the person (previous)"
    end

    test "non-deceased married partner selected when no marriage dates and multiple" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, deceased_wife} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", deceased: true})

      {:ok, living_wife} =
        People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      # Both married, no marriage_year
      {:ok, _} =
        Relationships.create_relationship(person, deceased_wife, "married", %{})

      {:ok, _} =
        Relationships.create_relationship(person, living_wife, "married", %{})

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      # Both should be in the graph
      assert find_person_node(graph, deceased_wife.id) != nil
      assert find_person_node(graph, living_wife.id) != nil

      # Living wife should be current (after person), deceased should be previous (before)
      focus = focus_node(graph)
      row_nodes = person_nodes(graph) |> Enum.filter(&(&1.row == focus.row))
      sorted = Enum.sort_by(row_nodes, & &1.col)
      ids_in_order = Enum.map(sorted, & &1.person.id)

      person_idx = Enum.find_index(ids_in_order, &(&1 == person.id))
      living_idx = Enum.find_index(ids_in_order, &(&1 == living_wife.id))

      assert living_idx > person_idx,
             "Non-deceased partner should be selected as current (after the person)"
    end
  end

  # ── Ex-partner children ordering ───────────────────────────────────

  describe "ex-partner children ordering" do
    test "ex-partner children appear LEFT of current-partner children" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, ex_wife} =
        People.create_person(family, %{given_name: "ExWife", surname: "E"})

      {:ok, current_wife} =
        People.create_person(family, %{given_name: "CurrentWife", surname: "C"})

      {:ok, _} =
        Relationships.create_relationship(person, ex_wife, "divorced", %{
          marriage_year: 1980,
          divorce_year: 1990
        })

      {:ok, _} =
        Relationships.create_relationship(person, current_wife, "married", %{
          marriage_year: 1995
        })

      # Child with ex
      {:ok, ex_child} = People.create_person(family, %{given_name: "ExKid", surname: "Doe"})
      {:ok, _} = Relationships.create_relationship(person, ex_child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(ex_wife, ex_child, "parent", %{role: "mother"})

      # Child with current wife
      {:ok, cur_child} = People.create_person(family, %{given_name: "CurKid", surname: "Doe"})

      {:ok, _} =
        Relationships.create_relationship(person, cur_child, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(current_wife, cur_child, "parent", %{role: "mother"})

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      # Find children in the descendant row
      focus = focus_node(graph)
      child_row = focus.row + 1
      child_nodes = person_nodes(graph) |> Enum.filter(&(&1.row == child_row))
      sorted_children = Enum.sort_by(child_nodes, & &1.col)
      child_ids = Enum.map(sorted_children, & &1.person.id)

      ex_child_idx = Enum.find_index(child_ids, &(&1 == ex_child.id))
      cur_child_idx = Enum.find_index(child_ids, &(&1 == cur_child.id))

      assert ex_child_idx < cur_child_idx,
             "Ex-partner children should appear LEFT (lower col) of current-partner children"
    end
  end

  # ── Depth controls ──────────────────────────────────────────────────

  describe "depth controls" do
    # 5-generation lineage:
    # great_grandparent -> grandparent -> parent -> child (focus) -> kid -> grandkid
    setup do
      family = family_fixture()

      {:ok, great_grandparent} =
        People.create_person(family, %{given_name: "GreatGrandparent", surname: "L"})

      {:ok, grandparent} =
        People.create_person(family, %{given_name: "Grandparent", surname: "L"})

      {:ok, parent} =
        People.create_person(family, %{given_name: "Parent", surname: "L"})

      {:ok, child} =
        People.create_person(family, %{given_name: "Child", surname: "L"})

      {:ok, kid} =
        People.create_person(family, %{given_name: "Kid", surname: "L"})

      {:ok, grandkid} =
        People.create_person(family, %{given_name: "Grandkid", surname: "L"})

      {:ok, _} =
        Relationships.create_relationship(great_grandparent, grandparent, "parent", %{
          role: "father"
        })

      {:ok, _} =
        Relationships.create_relationship(grandparent, parent, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(child, kid, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(kid, grandkid, "parent", %{role: "father"})

      %{
        family: family,
        great_grandparent: great_grandparent,
        grandparent: grandparent,
        parent: parent,
        child: child,
        kid: kid,
        grandkid: grandkid
      }
    end

    test "ancestors: 0 — no ancestors shown", %{family: family, child: child} do
      graph = PersonGraph.build(child, family.id, ancestors: 0)

      # Focus person should be the only ancestor-gen person
      focus = focus_node(graph)
      assert focus.person.id == child.id
      assert focus.row == 0

      # No parent nodes
      nodes = person_nodes(graph)
      refute Enum.any?(nodes, &(&1.person.id != child.id and &1.row < focus.row))
    end

    test "ancestors: 1 — parents shown, has_more_up for further ancestors", %{
      family: family,
      child: child,
      parent: parent
    } do
      graph = PersonGraph.build(child, family.id, ancestors: 1)

      parent_node = find_person_node(graph, parent.id)
      assert parent_node != nil
      assert parent_node.has_more_up == true

      # Grandparent should NOT be in graph
      assert find_person_node(graph, graph.focus_person.id) != nil
    end

    test "ancestors: 2 — parents + grandparents shown", %{
      family: family,
      child: child,
      parent: parent,
      grandparent: grandparent
    } do
      graph = PersonGraph.build(child, family.id, ancestors: 2)

      assert find_person_node(graph, parent.id) != nil
      assert find_person_node(graph, grandparent.id) != nil

      # Grandparent should have has_more_up since great_grandparent exists
      gp_node = find_person_node(graph, grandparent.id)
      assert gp_node.has_more_up == true
    end

    test "ancestors: 3 — three generations up", %{
      family: family,
      child: child,
      parent: parent,
      grandparent: grandparent,
      great_grandparent: great_grandparent
    } do
      graph = PersonGraph.build(child, family.id, ancestors: 3)

      assert find_person_node(graph, parent.id) != nil
      assert find_person_node(graph, grandparent.id) != nil
      assert find_person_node(graph, great_grandparent.id) != nil

      # Great-grandparent has no further ancestors — has_more_up should be false
      ggp_node = find_person_node(graph, great_grandparent.id)
      assert ggp_node.has_more_up == false
    end

    test "descendants: 0 — no children shown", %{family: family, child: child} do
      graph = PersonGraph.build(child, family.id, descendants: 0)

      nodes = person_nodes(graph)
      # Only focus person and ancestors
      refute Enum.any?(nodes, fn n -> n.row > focus_node(graph).row end)
    end

    test "descendants: 2 — grandchildren visible", %{
      family: family,
      child: child,
      kid: kid,
      grandkid: grandkid
    } do
      graph = PersonGraph.build(child, family.id, descendants: 2)

      assert find_person_node(graph, kid.id) != nil
      assert find_person_node(graph, grandkid.id) != nil
    end

    test "default opts (no opts) — ancestors: 2, descendants: 2", %{
      family: family,
      child: child,
      parent: parent,
      grandparent: grandparent,
      kid: kid,
      grandkid: grandkid
    } do
      graph = PersonGraph.build(child, family.id)

      # Ancestors: 2 levels
      assert find_person_node(graph, parent.id) != nil
      assert find_person_node(graph, grandparent.id) != nil

      # Descendants: 2 levels — both kid and grandkid visible
      assert find_person_node(graph, kid.id) != nil
      assert find_person_node(graph, grandkid.id) != nil
    end

    test "at_limit children include ex-partners" do
      family = family_fixture()

      # Parents
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})

      # Two sons (siblings)
      {:ok, gilbert} = People.create_person(family, %{given_name: "Gilbert", surname: "D"})
      {:ok, humphrey} = People.create_person(family, %{given_name: "Humphrey", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, gilbert, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, gilbert, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(dad, humphrey, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, humphrey, "parent", %{role: "mother"})

      # Greta: divorced from Gilbert, married to Humphrey
      {:ok, greta} = People.create_person(family, %{given_name: "Greta", surname: "W"})

      {:ok, _} =
        Relationships.create_relationship(gilbert, greta, "divorced", %{
          marriage_year: 1966,
          divorce_year: 1975
        })

      {:ok, _} =
        Relationships.create_relationship(humphrey, greta, "married", %{marriage_year: 1976})

      # Build graph focused on Mom with descendants: 1 (children at boundary)
      graph = PersonGraph.build(mom, family.id, ancestors: 0, descendants: 1)

      # Gilbert and Humphrey should be in the graph
      assert find_person_node(graph, gilbert.id) != nil
      assert find_person_node(graph, humphrey.id) != nil

      # Greta should appear in the graph (as partner at the limit)
      greta_nodes =
        person_nodes(graph) |> Enum.filter(&(&1.person.id == greta.id))

      assert length(greta_nodes) >= 1
    end

    test "at_limit children show multiple partners" do
      family = family_fixture()

      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})

      {:ok, son} = People.create_person(family, %{given_name: "Son", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, son, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, son, "parent", %{role: "mother"})

      # Son: divorced from Jane (1980), married to Mary (1990)
      {:ok, jane} = People.create_person(family, %{given_name: "Jane", surname: "W"})
      {:ok, mary} = People.create_person(family, %{given_name: "Mary", surname: "W"})

      {:ok, _} =
        Relationships.create_relationship(son, jane, "divorced", %{
          marriage_year: 1980,
          divorce_year: 1988
        })

      {:ok, _} =
        Relationships.create_relationship(son, mary, "married", %{marriage_year: 1990})

      graph = PersonGraph.build(mom, family.id, ancestors: 0, descendants: 1)

      # Both Jane and Mary should appear as partners
      assert find_person_node(graph, jane.id) != nil or
               Enum.any?(person_nodes(graph), &(&1.person.id == jane.id))

      assert find_person_node(graph, mary.id) != nil or
               Enum.any?(person_nodes(graph), &(&1.person.id == mary.id))
    end
  end

  # ── Deeper-parent-first ordering ────────────────────────────────────

  describe "deeper-parent-first ordering" do
    test "deeper parent is person_a (placed first) in the ancestor couple" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "C"})
      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "C"})

      # Mom has 3 generations of ancestry
      {:ok, maternal_gm} =
        People.create_person(family, %{given_name: "MaternalGM", surname: "C"})

      {:ok, maternal_ggm} =
        People.create_person(family, %{given_name: "MaternalGGM", surname: "C"})

      {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(maternal_gm, mom, "parent", %{role: "mother"})

      {:ok, _} =
        Relationships.create_relationship(maternal_ggm, maternal_gm, "parent", %{role: "mother"})

      graph = PersonGraph.build(child, family.id, ancestors: 3)

      # Mom should appear in the graph (deeper lineage)
      mom_node = find_person_node(graph, mom.id)
      dad_node = find_person_node(graph, dad.id)
      assert mom_node != nil
      assert dad_node != nil

      # Mom (deeper lineage) should be at a lower column (placed first / left)
      assert mom_node.col < dad_node.col
    end

    test "single parent needs no sorting" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "C"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      graph = PersonGraph.build(child, family.id, ancestors: 1)

      assert find_person_node(graph, parent.id) != nil
    end

    test "depth probe terminates on cyclic data" do
      family = family_fixture()

      {:ok, person_a} = People.create_person(family, %{given_name: "PersonA", surname: "C"})
      {:ok, person_b} = People.create_person(family, %{given_name: "PersonB", surname: "C"})

      # A is parent of B AND B is parent of A — a cycle
      {:ok, _} =
        Relationships.create_relationship(person_a, person_b, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(person_b, person_a, "parent", %{role: "father"})

      # Should not stack overflow
      assert %PersonGraph{} = PersonGraph.build(person_a, family.id, ancestors: 3)
    end
  end

  # ── Cycle detection ─────────────────────────────────────────────────

  describe "cycle detection" do
    test "Type 1: cousins who marry — grandparents REUSED, zero dups" do
      family = family_fixture()

      # Grandparents
      {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "G"})
      {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "G"})
      {:ok, _} = Relationships.create_relationship(grandpa, grandma, "married", %{})

      # Two sons
      {:ok, son_c} = People.create_person(family, %{given_name: "SonC", surname: "G"})
      {:ok, son_d} = People.create_person(family, %{given_name: "SonD", surname: "G"})
      {:ok, _} = Relationships.create_relationship(grandpa, son_c, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, son_c, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(grandpa, son_d, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, son_d, "parent", %{role: "mother"})

      # Each son marries an unrelated wife
      {:ok, wife_c} = People.create_person(family, %{given_name: "WifeC", surname: "W"})
      {:ok, wife_d} = People.create_person(family, %{given_name: "WifeD", surname: "W"})
      {:ok, _} = Relationships.create_relationship(son_c, wife_c, "married", %{})
      {:ok, _} = Relationships.create_relationship(son_d, wife_d, "married", %{})

      # Each couple has a child (the cousins)
      {:ok, cousin_e} = People.create_person(family, %{given_name: "CousinE", surname: "G"})
      {:ok, _} = Relationships.create_relationship(son_c, cousin_e, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(wife_c, cousin_e, "parent", %{role: "mother"})

      {:ok, cousin_f} = People.create_person(family, %{given_name: "CousinF", surname: "G"})
      {:ok, _} = Relationships.create_relationship(son_d, cousin_f, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(wife_d, cousin_f, "parent", %{role: "mother"})

      # Cousins marry and have a child (the focus)
      {:ok, _} = Relationships.create_relationship(cousin_e, cousin_f, "married", %{})

      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "G"})
      {:ok, _} = Relationships.create_relationship(cousin_e, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(cousin_f, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 3, descendants: 0)

      # Rule 1: Same gen + compatible → REUSE. GP+GM appear ONCE each (no dups).
      # SonD is encountered a second time (as CousinF's parent) at gen 2 —
      # same gen where he already appears as GP's child → reused.
      assert dup_count(graph) == 0

      # Grandparents appear exactly once (not duplicated)
      grandpa_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == grandpa.id))
      grandma_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == grandma.id))
      assert length(grandpa_nodes) == 1
      assert length(grandma_nodes) == 1

      # Grid: 4 cols (gen 2 is widest: SonD, WifeD, WifeC, SonC) × 4 rows
      assert graph.grid_rows == 4
      assert graph.grid_cols == 4
    end

    test "Type 4: uncle marries niece — Uncle dup'd at gen 1, grandparents once" do
      family = family_fixture()

      # Grandparents
      {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "G"})
      {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "G"})
      {:ok, _} = Relationships.create_relationship(grandpa, grandma, "married", %{})

      # Brother and uncle (children of grandparents)
      {:ok, brother} = People.create_person(family, %{given_name: "Brother", surname: "G"})
      {:ok, uncle} = People.create_person(family, %{given_name: "Uncle", surname: "G"})
      {:ok, _} = Relationships.create_relationship(grandpa, brother, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, brother, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(grandpa, uncle, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, uncle, "parent", %{role: "mother"})

      # Brother marries a wife and has a niece
      {:ok, wife} = People.create_person(family, %{given_name: "Wife", surname: "W"})
      {:ok, _} = Relationships.create_relationship(brother, wife, "married", %{})
      {:ok, niece} = People.create_person(family, %{given_name: "Niece", surname: "G"})
      {:ok, _} = Relationships.create_relationship(brother, niece, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(wife, niece, "parent", %{role: "mother"})

      # Uncle marries the niece
      {:ok, _} = Relationships.create_relationship(uncle, niece, "married", %{})

      # Focus child of uncle and niece
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "G"})
      {:ok, _} = Relationships.create_relationship(uncle, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(niece, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 3)

      # Rule 3: Uncle dup'd at gen 1 (different gen from natural gen 2).
      # Brother reused (same gen, dual role: GP's child + Niece's parent).
      assert dup_count(graph) == 1

      # Uncle appears twice: original at gen 2 (with Brother), dup at gen 1 (with Niece)
      uncle_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == uncle.id))
      assert length(uncle_nodes) == 2
      assert Enum.count(uncle_nodes, & &1.duplicated) == 1
      assert Enum.count(uncle_nodes, &(not &1.duplicated)) == 1

      # Grandparents appear once (not duplicated)
      grandpa_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == grandpa.id))
      grandma_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == grandma.id))
      assert length(grandpa_nodes) == 1
      assert length(grandma_nodes) == 1

      # Grid: 3 cols × 4 rows
      assert graph.grid_cols == 3
      assert graph.grid_rows == 4
    end

    test "Type 5: siblings marry into same family — no duplication" do
      family = family_fixture()

      # Family A: two brothers
      {:ok, gp_a} = People.create_person(family, %{given_name: "GrandpaA", surname: "A"})
      {:ok, brother_x} = People.create_person(family, %{given_name: "BrotherX", surname: "A"})
      {:ok, brother_y} = People.create_person(family, %{given_name: "BrotherY", surname: "A"})
      {:ok, _} = Relationships.create_relationship(gp_a, brother_x, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gp_a, brother_y, "parent", %{role: "father"})

      # Family B: two sisters
      {:ok, gp_b} = People.create_person(family, %{given_name: "GrandpaB", surname: "B"})
      {:ok, sister_x} = People.create_person(family, %{given_name: "SisterX", surname: "B"})
      {:ok, sister_y} = People.create_person(family, %{given_name: "SisterY", surname: "B"})
      {:ok, _} = Relationships.create_relationship(gp_b, sister_x, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gp_b, sister_y, "parent", %{role: "father"})

      # BrotherX marries SisterX, BrotherY marries SisterY
      {:ok, _} = Relationships.create_relationship(brother_x, sister_x, "married", %{})
      {:ok, _} = Relationships.create_relationship(brother_y, sister_y, "married", %{})

      # Focus is child of BrotherX and SisterX
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "A"})
      {:ok, _} = Relationships.create_relationship(brother_x, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(sister_x, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 2)

      # No person should be duplicated
      assert dup_count(graph) == 0

      # Grid: 3 rows (gen 0, 1, 2)
      assert graph.grid_rows == 3
    end

    test "no-cycle family — no person is duplicated" do
      family = family_fixture()

      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})
      {:ok, _} = Relationships.create_relationship(dad, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 2)

      assert dup_count(graph) == 0
    end

    test "same person as both parents (bad data) — second entry is duplicated" do
      family = family_fixture()

      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "P"})

      rel = %Ancestry.Relationships.Relationship{
        person_a_id: parent.id,
        person_b_id: focus.id,
        type: "parent"
      }

      graph_data = %FamilyGraph{
        family_id: family.id,
        people_by_id: %{parent.id => parent, focus.id => focus},
        parents_by_child: %{focus.id => [{parent, rel}, {parent, rel}]},
        children_by_parent: %{parent.id => [focus]},
        partners_by_person: %{}
      }

      graph = PersonGraph.build(focus, graph_data, ancestors: 1)

      parent_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == parent.id))

      # Parent appears twice: once not duplicated, once duplicated
      assert length(parent_nodes) == 2
      assert Enum.count(parent_nodes, & &1.duplicated) == 1
      assert Enum.count(parent_nodes, &(not &1.duplicated)) == 1
    end

    test "self-ancestor (bad data) — stub is duplicated, no stack overflow" do
      family = family_fixture()

      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "F"})

      rel = %Ancestry.Relationships.Relationship{
        person_a_id: focus.id,
        person_b_id: focus.id,
        type: "parent"
      }

      graph_data = %FamilyGraph{
        family_id: family.id,
        people_by_id: %{focus.id => focus},
        parents_by_child: %{focus.id => [{focus, rel}]},
        children_by_parent: %{focus.id => [focus]},
        partners_by_person: %{}
      }

      # Should not stack overflow
      graph = PersonGraph.build(focus, graph_data, ancestors: 3)

      assert %PersonGraph{} = graph

      # Focus appears in ancestors as duplicated
      focus_dup_nodes =
        person_nodes(graph) |> Enum.filter(&(&1.person.id == focus.id and &1.duplicated))

      assert length(focus_dup_nodes) >= 1
    end

    test "Type 2: woman marries two brothers — no ancestor duplication in Phase 1" do
      family = family_fixture()

      # Grandparents
      {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "G"})
      {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "G"})
      {:ok, _} = Relationships.create_relationship(grandpa, grandma, "married", %{})

      # Two sons
      {:ok, brother1} = People.create_person(family, %{given_name: "Brother1", surname: "G"})
      {:ok, brother2} = People.create_person(family, %{given_name: "Brother2", surname: "G"})
      {:ok, _} = Relationships.create_relationship(grandpa, brother1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, brother1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(grandpa, brother2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, brother2, "parent", %{role: "mother"})

      # Mom marries Brother1 (divorced), then Brother2
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, _} = Relationships.create_relationship(brother1, mom, "divorced", %{})
      {:ok, _} = Relationships.create_relationship(brother2, mom, "married", %{})

      # Half-sibling is child of Brother1 + Mom
      {:ok, half_sibling} =
        People.create_person(family, %{given_name: "HalfSib", surname: "G"})

      {:ok, _} =
        Relationships.create_relationship(brother1, half_sibling, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(mom, half_sibling, "parent", %{role: "mother"})

      # Focus is child of Brother2 + Mom
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "G"})
      {:ok, _} = Relationships.create_relationship(brother2, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})

      # Build with ancestors: 2
      graph = PersonGraph.build(focus, family.id, ancestors: 2)

      # Only ancestor nodes should be checked for duplication
      ancestor_nodes =
        person_nodes(graph)
        |> Enum.filter(&(&1.row < focus_node(graph).row))

      # No ancestor should be duplicated
      assert Enum.all?(ancestor_nodes, &(not &1.duplicated))

      # Grid: 3 rows (gen 0, 1, 2)
      assert graph.grid_rows == 3
    end

    test "Type 3: double first cousins — grandparents REUSED (other: 0), zero dups" do
      family = family_fixture()

      # Grandparents-A with two sons
      {:ok, gpa_a} = People.create_person(family, %{given_name: "GPA_A", surname: "A"})
      {:ok, gma_a} = People.create_person(family, %{given_name: "GMA_A", surname: "A"})
      {:ok, _} = Relationships.create_relationship(gpa_a, gma_a, "married", %{})
      {:ok, bro_x} = People.create_person(family, %{given_name: "BroX", surname: "A"})
      {:ok, bro_y} = People.create_person(family, %{given_name: "BroY", surname: "A"})
      {:ok, _} = Relationships.create_relationship(gpa_a, bro_x, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gma_a, bro_x, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(gpa_a, bro_y, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gma_a, bro_y, "parent", %{role: "mother"})

      # Grandparents-B with two daughters
      {:ok, gpa_b} = People.create_person(family, %{given_name: "GPA_B", surname: "B"})
      {:ok, gma_b} = People.create_person(family, %{given_name: "GMA_B", surname: "B"})
      {:ok, _} = Relationships.create_relationship(gpa_b, gma_b, "married", %{})
      {:ok, sis_x} = People.create_person(family, %{given_name: "SisX", surname: "B"})
      {:ok, sis_y} = People.create_person(family, %{given_name: "SisY", surname: "B"})
      {:ok, _} = Relationships.create_relationship(gpa_b, sis_x, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gma_b, sis_x, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(gpa_b, sis_y, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gma_b, sis_y, "parent", %{role: "mother"})

      # BroX marries SisX → Parent1; BroY marries SisY → Parent2
      {:ok, _} = Relationships.create_relationship(bro_x, sis_x, "married", %{})
      {:ok, parent1} = People.create_person(family, %{given_name: "Parent1", surname: "AB"})
      {:ok, _} = Relationships.create_relationship(bro_x, parent1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(sis_x, parent1, "parent", %{role: "mother"})

      {:ok, _} = Relationships.create_relationship(bro_y, sis_y, "married", %{})
      {:ok, parent2} = People.create_person(family, %{given_name: "Parent2", surname: "AB"})
      {:ok, _} = Relationships.create_relationship(bro_y, parent2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(sis_y, parent2, "parent", %{role: "mother"})

      # Parent1 marries Parent2 → Focus
      {:ok, _} = Relationships.create_relationship(parent1, parent2, "married", %{})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "AB"})
      {:ok, _} = Relationships.create_relationship(parent1, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(parent2, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 3, descendants: 0)

      # With other: 0 (default), BroY and SisY are NOT pre-visited as
      # laterals. They're discovered as Parent2's parents at gen 2. Their
      # own parents (GPA/GMA) are already at gen 3 → same gen → reused.
      # Rule 1: same gen + compatible → no dups.
      assert dup_count(graph) == 0

      # Each grandparent appears exactly once
      for gp <- [gpa_a, gma_a, gpa_b, gma_b] do
        gp_nodes = Enum.filter(person_nodes(graph), &(&1.person.id == gp.id))

        assert length(gp_nodes) == 1,
               "Expected #{gp.given_name} to appear exactly once (reused)"
      end

      # Grid: 4 cols × 4 rows
      assert graph.grid_rows == 4
      assert graph.grid_cols == 4
    end

    test "three parents (bad data) — only first two are used" do
      family = family_fixture()

      {:ok, parent_a} = People.create_person(family, %{given_name: "ParentA", surname: "P"})
      {:ok, parent_b} = People.create_person(family, %{given_name: "ParentB", surname: "P"})
      {:ok, parent_c} = People.create_person(family, %{given_name: "ParentC", surname: "P"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "P"})

      rel_a = %Ancestry.Relationships.Relationship{
        person_a_id: parent_a.id,
        person_b_id: focus.id,
        type: "parent"
      }

      rel_b = %Ancestry.Relationships.Relationship{
        person_a_id: parent_b.id,
        person_b_id: focus.id,
        type: "parent"
      }

      rel_c = %Ancestry.Relationships.Relationship{
        person_a_id: parent_c.id,
        person_b_id: focus.id,
        type: "parent"
      }

      graph_data = %FamilyGraph{
        family_id: family.id,
        people_by_id: %{
          parent_a.id => parent_a,
          parent_b.id => parent_b,
          parent_c.id => parent_c,
          focus.id => focus
        },
        parents_by_child: %{
          focus.id => [{parent_a, rel_a}, {parent_b, rel_b}, {parent_c, rel_c}]
        },
        children_by_parent: %{
          parent_a.id => [focus],
          parent_b.id => [focus],
          parent_c.id => [focus]
        },
        partners_by_person: %{}
      }

      graph = PersonGraph.build(focus, graph_data, ancestors: 1)

      # Only the first two parents become the ancestor couple
      assert find_person_node(graph, parent_a.id) != nil
      assert find_person_node(graph, parent_b.id) != nil
    end
  end

  # ── Grid structure ──────────────────────────────────────────────────

  describe "grid structure" do
    test "simple family produces correct grid dimensions" do
      family = family_fixture()

      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})
      {:ok, _} = Relationships.create_relationship(dad, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 1, descendants: 0)

      # Parents at row 0, focus at row 1 = 2 rows
      assert graph.grid_rows == 2
      # At least 2 columns (for the parent couple)
      assert graph.grid_cols >= 2

      # Focus should be at a lower row than parents
      focus_n = focus_node(graph)
      dad_n = find_person_node(graph, dad.id)
      mom_n = find_person_node(graph, mom.id)

      assert focus_n.row > dad_n.row
      assert dad_n.row == mom_n.row
    end

    test "focus node is marked correctly" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Solo", surname: "S"})

      graph = PersonGraph.build(person, family.id, ancestors: 0)

      focus = focus_node(graph)
      assert focus != nil
      assert focus.person.id == person.id
      assert focus.focus == true
    end

    test "edges are generated for parent-child and couple relationships" do
      family = family_fixture()

      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})
      {:ok, _} = Relationships.create_relationship(dad, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 1, descendants: 0)

      # Should have parent-child edges
      pc_edges = parent_child_edges(graph)
      assert length(pc_edges) >= 2

      # Should have a couple edge
      c_edges = couple_edges(graph)
      assert length(c_edges) >= 1
    end

    test "separator nodes fill remaining grid cells" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Solo", surname: "S"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "S"})
      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      graph = PersonGraph.build(person, family.id, ancestors: 1, descendants: 0)

      separator_nodes = Enum.filter(graph.nodes, &(&1.type == :separator))

      # Total nodes should equal grid_cols * grid_rows
      total_cells = graph.grid_cols * graph.grid_rows
      total_nodes = length(graph.nodes)
      assert total_nodes == total_cells
      assert length(separator_nodes) == total_cells - length(person_nodes(graph))
    end
  end

  # ── has_more indicators ─────────────────────────────────────────────

  describe "has_more indicators" do
    test "has_more_down is false when all children are visible via other parent path" do
      family = family_fixture()

      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "F"})
      {:ok, spouse} = People.create_person(family, %{given_name: "Spouse", surname: "S"})
      {:ok, _} = Relationships.create_relationship(focus, spouse, "married", %{})

      {:ok, kid} = People.create_person(family, %{given_name: "Kid", surname: "F"})
      {:ok, _} = Relationships.create_relationship(focus, kid, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(spouse, kid, "parent", %{role: "mother"})

      graph = PersonGraph.build(focus, family.id, ancestors: 0, descendants: 1)

      assert find_person_node(graph, kid.id) != nil

      spouse_node = find_person_node(graph, spouse.id)
      assert spouse_node != nil

      refute spouse_node.has_more_down,
             "Spouse should not have has_more_down when all children are visible"
    end

    test "ancestor at depth boundary shows has_more_up when more ancestors exist" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "L"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "L"})

      {:ok, grandparent} =
        People.create_person(family, %{given_name: "Grandparent", surname: "L"})

      {:ok, great_grandparent} =
        People.create_person(family, %{given_name: "GreatGrandparent", surname: "L"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(grandparent, parent, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(great_grandparent, grandparent, "parent", %{
          role: "father"
        })

      # ancestors: 1 shows parent only
      graph = PersonGraph.build(child, family.id, ancestors: 1)

      parent_node = find_person_node(graph, parent.id)
      assert parent_node != nil
      assert parent_node.has_more_up == true
    end

    test "ancestor at depth boundary shows has_more_up false when no more ancestors" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "L"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "L"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      graph = PersonGraph.build(child, family.id, ancestors: 1)

      parent_node = find_person_node(graph, parent.id)
      assert parent_node != nil
      assert parent_node.has_more_up == false
    end
  end

  # ── Partner ordering ───────────────────────────────────────────────

  describe "partner ordering" do
    test "current partner appears after person, ex-partner appears before" do
      family = family_fixture()

      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, ex_wife} = People.create_person(family, %{given_name: "ExWife", surname: "E"})

      {:ok, current_wife} =
        People.create_person(family, %{given_name: "CurrentWife", surname: "C"})

      {:ok, _} =
        Relationships.create_relationship(person, ex_wife, "divorced", %{
          marriage_year: 1980,
          divorce_year: 1990
        })

      {:ok, _} =
        Relationships.create_relationship(person, current_wife, "married", %{
          marriage_year: 1995
        })

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      focus = focus_node(graph)
      row_nodes = person_nodes(graph) |> Enum.filter(&(&1.row == focus.row))
      sorted = Enum.sort_by(row_nodes, & &1.col)
      ids_in_order = Enum.map(sorted, & &1.person.id)

      person_idx = Enum.find_index(ids_in_order, &(&1 == person.id))
      ex_idx = Enum.find_index(ids_in_order, &(&1 == ex_wife.id))
      current_idx = Enum.find_index(ids_in_order, &(&1 == current_wife.id))

      assert ex_idx < person_idx, "Ex-partner should appear before the person"
      assert current_idx > person_idx, "Current partner should appear after the person"
    end

    test "separated partner appears before person, current after" do
      family = family_fixture()

      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})

      {:ok, first_wife} =
        People.create_person(family, %{given_name: "FirstWife", surname: "F"})

      {:ok, second_wife} =
        People.create_person(family, %{given_name: "SecondWife", surname: "S"})

      {:ok, _} =
        Relationships.create_relationship(person, first_wife, "separated", %{
          marriage_year: 1980
        })

      {:ok, _} =
        Relationships.create_relationship(person, second_wife, "married", %{marriage_year: 1995})

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      focus = focus_node(graph)
      row_nodes = person_nodes(graph) |> Enum.filter(&(&1.row == focus.row))
      sorted = Enum.sort_by(row_nodes, & &1.col)
      ids_in_order = Enum.map(sorted, & &1.person.id)

      person_idx = Enum.find_index(ids_in_order, &(&1 == person.id))
      first_idx = Enum.find_index(ids_in_order, &(&1 == first_wife.id))
      second_idx = Enum.find_index(ids_in_order, &(&1 == second_wife.id))

      assert first_idx < person_idx, "Separated partner should appear before the person"
      assert second_idx > person_idx, "Current partner should appear after the person"
    end
  end

  # ── Partner separators ─────────────────────────────────────────────

  describe "partner separators" do
    test "separator between person and ex-partner" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, ex} = People.create_person(family, %{given_name: "Ex", surname: "E"})
      {:ok, _} = Relationships.create_relationship(person, ex, "divorced", %{})
      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, _} = Relationships.create_relationship(person, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(ex, child, "parent", %{role: "mother"})

      graph = PersonGraph.build(person, family.id, ancestors: 0, descendants: 1)

      # Find separator between ex and person
      separators = Enum.filter(graph.nodes, &(&1.type == :separator))

      partner_sep =
        Enum.find(separators, fn n ->
          String.contains?(n.id, "sep-#{person.id}-#{ex.id}") or
            String.contains?(n.id, "sep-#{ex.id}-#{person.id}")
        end)

      assert partner_sep != nil, "Expected a separator between person and ex-partner"

      # Separator should be at the same row as person and ex
      person_node =
        Enum.find(
          graph.nodes,
          &(&1.type == :person and &1.person.id == person.id and not &1.duplicated)
        )

      assert partner_sep.row == person_node.row

      # Separator column should be between ex and person
      ex_node = Enum.find(graph.nodes, &(&1.type == :person and &1.person.id == ex.id))
      assert partner_sep.col > ex_node.col
      assert partner_sep.col < person_node.col
    end
  end
end
