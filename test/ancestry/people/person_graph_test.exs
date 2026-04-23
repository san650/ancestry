defmodule Ancestry.People.PersonGraphTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.PersonGraph
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
      tree = PersonGraph.build(person, family1.id)

      # Ancestors should only have f1_parent
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == f1_parent.id
      assert tree.ancestors.couple.person_b == nil

      # Descendants (solo_children) should only have f1_child
      assert length(tree.center.solo_children) == 1
      assert hd(tree.center.solo_children).person.id == f1_child.id
    end

    test "build/2 accepts a pre-built FamilyGraph" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      graph = FamilyGraph.for_family(family.id)
      tree = PersonGraph.build(person, graph)
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == parent.id
    end
  end

  describe "multiple current partners (widowed and remarried)" do
    test "latest partner by marriage year is main partner, others are previous partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, first_wife} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", deceased: true})

      {:ok, second_wife} =
        People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      # First marriage (1985) — wife later died
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

      tree = PersonGraph.build(person, family.id)

      # Latest partner (second wife, married 1995) should be the main partner
      assert tree.center.partner.id == second_wife.id

      # First wife should be in previous_partners
      assert length(tree.center.previous_partners) == 1
      [prev] = tree.center.previous_partners
      assert prev.person.id == first_wife.id

      # Children grouped correctly
      assert length(tree.center.partner_children) == 1
      assert hd(tree.center.partner_children).person.id == child2.id

      assert length(prev.children) == 1
      assert hd(prev.children).person.id == child1.id
    end

    test "falls back to person id when no marriage dates" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, first_wife} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      {:ok, second_wife} = People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      # No marriage dates
      {:ok, _} = Relationships.create_relationship(person, first_wife, "married", %{})
      {:ok, _} = Relationships.create_relationship(person, second_wife, "married", %{})

      tree = PersonGraph.build(person, family.id)

      # Higher person.id should be the main partner (latest added)
      latest = Enum.max_by([first_wife, second_wife], & &1.id)
      earlier = Enum.min_by([first_wife, second_wife], & &1.id)

      assert tree.center.partner.id == latest.id
      assert length(tree.center.previous_partners) == 1
      assert hd(tree.center.previous_partners).person.id == earlier.id
    end

    test "single partner produces no previous_partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, wife} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      {:ok, _} = Relationships.create_relationship(person, wife, "married", %{})

      tree = PersonGraph.build(person, family.id)

      assert tree.center.partner.id == wife.id
      assert tree.center.previous_partners == []
    end

    test "no partners produces nil partner and empty previous_partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      tree = PersonGraph.build(person, family.id)

      assert tree.center.partner == nil
      assert tree.center.previous_partners == []
    end
  end

  describe "depth controls" do
    # 5-generation lineage:
    # great_grandparent -> grandparent -> parent -> child (focus) -> kid -> grandkid
    # All solo children (no partners), only parent relationships.
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

    test "ancestors: 0 → tree.ancestors == nil", %{family: family, child: child} do
      tree = PersonGraph.build(child, family.id, ancestors: 0)
      assert tree.ancestors == nil
    end

    test "ancestors: 1 → parents shown, parent_trees == []", %{
      family: family,
      child: child,
      parent: parent
    } do
      tree = PersonGraph.build(child, family.id, ancestors: 1)
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == parent.id
      assert tree.ancestors.parent_trees == []
    end

    test "ancestors: 2 → parents + grandparents shown", %{
      family: family,
      child: child,
      parent: parent,
      grandparent: grandparent
    } do
      tree = PersonGraph.build(child, family.id, ancestors: 2)
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == parent.id
      assert length(tree.ancestors.parent_trees) == 1
      [%{tree: gp_tree}] = tree.ancestors.parent_trees
      assert gp_tree.couple.person_a.id == grandparent.id
      assert gp_tree.parent_trees == []
    end

    test "ancestors: 3 → three generations up", %{
      family: family,
      child: child,
      parent: parent,
      grandparent: grandparent,
      great_grandparent: great_grandparent
    } do
      tree = PersonGraph.build(child, family.id, ancestors: 3)
      assert tree.ancestors.couple.person_a.id == parent.id
      [%{tree: gp_tree}] = tree.ancestors.parent_trees
      assert gp_tree.couple.person_a.id == grandparent.id
      [%{tree: ggp_tree}] = gp_tree.parent_trees
      assert ggp_tree.couple.person_a.id == great_grandparent.id
      assert ggp_tree.parent_trees == []
    end

    test "descendants: 0 → no children", %{family: family, child: child} do
      tree = PersonGraph.build(child, family.id, descendants: 0)
      assert tree.center.solo_children == []
      assert tree.center.partner_children == []
    end

    test "descendants: 2 → grandchildren visible", %{
      family: family,
      child: child,
      kid: kid,
      grandkid: grandkid
    } do
      tree = PersonGraph.build(child, family.id, descendants: 2)
      assert length(tree.center.solo_children) == 1
      [kid_unit] = tree.center.solo_children
      # kid should be fully expanded (not at limit), so it has a focus field
      assert kid_unit.focus.id == kid.id
      # grandkid should appear as kid's child (at the limit)
      assert length(kid_unit.solo_children) == 1
      [grandkid_unit] = kid_unit.solo_children
      assert grandkid_unit.person.id == grandkid.id
    end

    test "default opts (no opts) → ancestors: 2, descendants: 1", %{
      family: family,
      child: child,
      parent: parent,
      grandparent: grandparent,
      kid: kid
    } do
      tree = PersonGraph.build(child, family.id)
      # Ancestors: 2 levels → parent and grandparent visible
      assert tree.ancestors.couple.person_a.id == parent.id
      assert length(tree.ancestors.parent_trees) == 1
      [%{tree: gp_tree}] = tree.ancestors.parent_trees
      assert gp_tree.couple.person_a.id == grandparent.id
      assert gp_tree.parent_trees == []
      # Descendants: 1 level → kid visible but no grandkid
      assert length(tree.center.solo_children) == 1
      [kid_unit] = tree.center.solo_children
      assert kid_unit.person.id == kid.id
      assert kid_unit.children == nil
    end
  end

  describe "deeper-parent-first ordering" do
    test "deeper parent becomes person_a in the ancestor couple" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "C"})
      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "C"})

      # Mom has 3 generations of ancestry: mom → maternal_gm → maternal_ggm
      {:ok, maternal_gm} =
        People.create_person(family, %{given_name: "MaternalGM", surname: "C"})

      {:ok, maternal_ggm} =
        People.create_person(family, %{given_name: "MaternalGGM", surname: "C"})

      # Dad has no ancestry above
      {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(maternal_gm, mom, "parent", %{role: "mother"})

      {:ok, _} =
        Relationships.create_relationship(maternal_ggm, maternal_gm, "parent", %{role: "mother"})

      tree = PersonGraph.build(child, family.id, ancestors: 3)

      # Mom (3 generations deep) should be person_a — deeper lineage first
      assert tree.ancestors.couple.person_a.id == mom.id
    end

    test "single parent needs no sorting" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "C"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      tree = PersonGraph.build(child, family.id, ancestors: 1)

      assert tree.ancestors.couple.person_a.id == parent.id
      assert tree.ancestors.couple.person_b == nil
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

  defp family_fixture(attrs \\ %{}) do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end
end
