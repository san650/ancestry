defmodule Ancestry.People.FamilyGraphTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.Relationships

  describe "build/2 with empty data" do
    test "returns empty graph" do
      graph = FamilyGraph.build([], [])

      assert graph.nodes == %{}
      assert graph.unions == []
      assert graph.child_edges == []
      assert graph.components == []
      assert graph.unconnected == []
    end
  end

  describe "build/2 with people but no relationships" do
    test "all people are unconnected" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      graph = FamilyGraph.build([alice, bob], [])

      assert graph.nodes == %{}
      assert graph.unions == []
      assert graph.child_edges == []
      assert graph.components == []
      assert length(graph.unconnected) == 2
      unconnected_ids = Enum.map(graph.unconnected, & &1.id) |> Enum.sort()
      assert unconnected_ids == Enum.sort([alice.id, bob.id])
    end
  end

  describe "build/2 with partner relationship" do
    test "creates union and two person nodes" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, rel} = Relationships.create_relationship(alice, bob, "partner")

      graph = FamilyGraph.build([alice, bob], [rel])

      # Should have 2 nodes
      assert map_size(graph.nodes) == 2
      assert graph.nodes[alice.id].person.id == alice.id
      assert graph.nodes[bob.id].person.id == bob.id

      # Both should be generation 0 (root nodes)
      assert graph.nodes[alice.id].generation == 0
      assert graph.nodes[bob.id].generation == 0

      # Should have 1 union
      assert length(graph.unions) == 1
      [union] = graph.unions
      assert union.type == :partner

      assert MapSet.new([union.person_a_id, union.person_b_id]) ==
               MapSet.new([alice.id, bob.id])

      # No child edges
      assert graph.child_edges == []

      # 1 component containing both
      assert length(graph.components) == 1
      [component] = graph.components
      assert MapSet.new(component) == MapSet.new([alice.id, bob.id])

      # No unconnected people
      assert graph.unconnected == []
    end
  end

  describe "build/2 with parent-child and both parents" do
    test "child edge from union, correct generations" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      {:ok, partner_rel} = Relationships.create_relationship(father, mother, "partner")

      {:ok, parent_rel1} =
        Relationships.create_relationship(father, child, "parent", %{role: "father"})

      {:ok, parent_rel2} =
        Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      graph = FamilyGraph.build([father, mother, child], [partner_rel, parent_rel1, parent_rel2])

      # 3 nodes
      assert map_size(graph.nodes) == 3

      # Parents at generation 0, child at generation 1
      assert graph.nodes[father.id].generation == 0
      assert graph.nodes[mother.id].generation == 0
      assert graph.nodes[child.id].generation == 1

      # 1 union
      assert length(graph.unions) == 1
      [union] = graph.unions

      # 1 child edge from the union
      assert length(graph.child_edges) == 1
      [edge] = graph.child_edges
      assert edge.from == {:union, union.id}
      assert edge.to == child.id

      # All in one component
      assert length(graph.components) == 1
    end
  end

  describe "build/2 with solo parent (one known parent)" do
    test "child edge from {:person, parent_id}" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      {:ok, parent_rel} =
        Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      graph = FamilyGraph.build([parent, child], [parent_rel])

      assert map_size(graph.nodes) == 2
      assert graph.nodes[parent.id].generation == 0
      assert graph.nodes[child.id].generation == 1

      # Child edge from person, not union
      assert length(graph.child_edges) == 1
      [edge] = graph.child_edges
      assert edge.from == {:person, parent.id}
      assert edge.to == child.id

      # No unions
      assert graph.unions == []

      # All in one component
      assert length(graph.components) == 1
    end
  end

  describe "build/2 with ex_partner relationship" do
    test "creates separate union with :ex_partner type" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, rel} =
        Relationships.create_relationship(alice, bob, "ex_partner", %{
          marriage_year: 2010,
          divorce_year: 2015
        })

      graph = FamilyGraph.build([alice, bob], [rel])

      assert length(graph.unions) == 1
      [union] = graph.unions
      assert union.type == :ex_partner

      assert MapSet.new([union.person_a_id, union.person_b_id]) ==
               MapSet.new([alice.id, bob.id])
    end
  end

  describe "build/2 with disconnected families" do
    test "produces separate components" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, carol} = People.create_person(family, %{given_name: "Carol", surname: "C"})
      {:ok, dave} = People.create_person(family, %{given_name: "Dave", surname: "D"})

      {:ok, rel1} = Relationships.create_relationship(alice, bob, "partner")
      {:ok, rel2} = Relationships.create_relationship(carol, dave, "partner")

      graph = FamilyGraph.build([alice, bob, carol, dave], [rel1, rel2])

      assert length(graph.components) == 2

      component_sets = Enum.map(graph.components, &MapSet.new/1) |> Enum.sort()

      expected_sets =
        [MapSet.new([alice.id, bob.id]), MapSet.new([carol.id, dave.id])] |> Enum.sort()

      assert component_sets == expected_sets
    end
  end

  describe "build/2 with three generations" do
    test "correct generation numbers (0, 1, 2)" do
      family = family_fixture()
      {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "G"})
      {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "G"})
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "G"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "G"})

      {:ok, gp_rel} = Relationships.create_relationship(grandpa, grandma, "partner")

      {:ok, gp_father_rel} =
        Relationships.create_relationship(grandpa, father, "parent", %{role: "father"})

      {:ok, gp_mother_rel} =
        Relationships.create_relationship(grandma, father, "parent", %{role: "mother"})

      {:ok, p_rel} = Relationships.create_relationship(father, mother, "partner")

      {:ok, p_father_rel} =
        Relationships.create_relationship(father, child, "parent", %{role: "father"})

      {:ok, p_mother_rel} =
        Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      all_rels = [gp_rel, gp_father_rel, gp_mother_rel, p_rel, p_father_rel, p_mother_rel]
      graph = FamilyGraph.build([grandpa, grandma, father, mother, child], all_rels)

      # Grandparents at generation 0
      assert graph.nodes[grandpa.id].generation == 0
      assert graph.nodes[grandma.id].generation == 0

      # Father at generation 1 (child of grandparents)
      assert graph.nodes[father.id].generation == 1

      # Mother at generation 1 (partner of father, same generation)
      assert graph.nodes[mother.id].generation == 1

      # Grandchild at generation 2
      assert graph.nodes[child.id].generation == 2

      # All in one component
      assert length(graph.components) == 1
    end
  end

  describe "build/2 with two parents but no union between them" do
    test "creates solo edges from each parent" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      # No partner/ex_partner relationship between parents — just parent rels
      {:ok, parent_rel1} =
        Relationships.create_relationship(father, child, "parent", %{role: "father"})

      {:ok, parent_rel2} =
        Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      graph = FamilyGraph.build([father, mother, child], [parent_rel1, parent_rel2])

      # No unions since no partner/ex_partner relationship
      assert graph.unions == []

      # Two child edges, one from each parent
      assert length(graph.child_edges) == 2

      edge_froms = Enum.map(graph.child_edges, & &1.from) |> Enum.sort()

      expected_froms =
        [{:person, father.id}, {:person, mother.id}] |> Enum.sort()

      assert edge_froms == expected_froms

      # Both edges point to the child
      assert Enum.all?(graph.child_edges, &(&1.to == child.id))

      # All in one component
      assert length(graph.components) == 1
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
