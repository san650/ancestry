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
      assert tree.ancestors.couple.person_a.person.id == f1_parent.id
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
      assert tree.ancestors.couple.person_a.person.id == parent.id
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
      assert tree.ancestors.couple.person_a.person.id == parent.id
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
      assert tree.ancestors.couple.person_a.person.id == parent.id
      assert length(tree.ancestors.parent_trees) == 1
      [%{tree: gp_tree}] = tree.ancestors.parent_trees
      assert gp_tree.couple.person_a.person.id == grandparent.id
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
      assert tree.ancestors.couple.person_a.person.id == parent.id
      [%{tree: gp_tree}] = tree.ancestors.parent_trees
      assert gp_tree.couple.person_a.person.id == grandparent.id
      [%{tree: ggp_tree}] = gp_tree.parent_trees
      assert ggp_tree.couple.person_a.person.id == great_grandparent.id
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
      assert tree.ancestors.couple.person_a.person.id == parent.id
      assert length(tree.ancestors.parent_trees) == 1
      [%{tree: gp_tree}] = tree.ancestors.parent_trees
      assert gp_tree.couple.person_a.person.id == grandparent.id
      assert gp_tree.parent_trees == []
      # Descendants: 1 level → kid visible but no grandkid
      assert length(tree.center.solo_children) == 1
      [kid_unit] = tree.center.solo_children
      assert kid_unit.person.id == kid.id
      assert kid_unit.children == nil
    end

    test "at_limit children include ex-partners in previous_partners", %{family: _family} do
      # Override the lineage setup — we need our own family structure
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

      # Greta: divorced from Gilbert (married 1966, divorced 1975), married to Humphrey (1976)
      {:ok, greta} = People.create_person(family, %{given_name: "Greta", surname: "W"})

      {:ok, _} =
        Relationships.create_relationship(gilbert, greta, "divorced", %{
          marriage_year: 1966,
          divorce_year: 1975
        })

      {:ok, _} =
        Relationships.create_relationship(humphrey, greta, "married", %{marriage_year: 1976})

      # Build tree focused on Mom with descendants: 1 (children at boundary)
      tree = PersonGraph.build(mom, family.id, ancestors: 0, descendants: 1)

      # Find Gilbert and Humphrey in the partner_children
      children = tree.center.partner_children
      gilbert_unit = Enum.find(children, &(&1.person.id == gilbert.id))
      humphrey_unit = Enum.find(children, &(&1.person.id == humphrey.id))

      # Gilbert (earlier in birth_year order) shows Greta first — not duplicated
      assert gilbert_unit.partner.id == greta.id
      assert gilbert_unit.partner_duplicated == false
      assert gilbert_unit.previous_partners == []

      # Humphrey (later) also shows Greta — marked duplicated
      assert humphrey_unit.partner.id == greta.id
      assert humphrey_unit.partner_duplicated == true
      assert humphrey_unit.previous_partners == []
    end

    test "at_limit children show multiple partners as main + previous_partners" do
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

      tree = PersonGraph.build(mom, family.id, ancestors: 0, descendants: 1)

      children = tree.center.partner_children
      son_unit = Enum.find(children, &(&1.person.id == son.id))

      # Main partner is Mary (latest marriage year)
      assert son_unit.partner.id == mary.id
      # Jane is in previous_partners
      assert length(son_unit.previous_partners) == 1
      [prev] = son_unit.previous_partners
      assert prev.person.id == jane.id
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
      assert tree.ancestors.couple.person_a.person.id == mom.id
    end

    test "single parent needs no sorting" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "C"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      tree = PersonGraph.build(child, family.id, ancestors: 1)

      assert tree.ancestors.couple.person_a.person.id == parent.id
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

  describe "cycle detection" do
    test "Type 1: cousins who marry — shared grandparents, one duplicated" do
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

      tree = PersonGraph.build(focus, family.id, ancestors: 3)

      # Collect all ancestor person entries
      entries = collect_ancestor_persons(tree.ancestors)
      grandpa_entries = Enum.filter(entries, &(&1.person.id == grandpa.id))
      grandma_entries = Enum.filter(entries, &(&1.person.id == grandma.id))

      # Grandparents appear twice — once not duplicated, once duplicated
      assert length(grandpa_entries) == 2
      assert Enum.count(grandpa_entries, & &1.duplicated) == 1
      assert Enum.count(grandpa_entries, &(not &1.duplicated)) == 1

      assert length(grandma_entries) == 2
      assert Enum.count(grandma_entries, & &1.duplicated) == 1
      assert Enum.count(grandma_entries, &(not &1.duplicated)) == 1
    end

    test "Type 4: uncle marries niece — grandparents appear with one duplicated" do
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

      tree = PersonGraph.build(focus, family.id, ancestors: 3)

      entries = collect_ancestor_persons(tree.ancestors)
      grandpa_entries = Enum.filter(entries, &(&1.person.id == grandpa.id))
      grandma_entries = Enum.filter(entries, &(&1.person.id == grandma.id))

      # Grandparents appear twice — once not duplicated, once duplicated
      assert length(grandpa_entries) == 2
      assert Enum.count(grandpa_entries, & &1.duplicated) == 1

      assert length(grandma_entries) == 2
      assert Enum.count(grandma_entries, & &1.duplicated) == 1
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

      tree = PersonGraph.build(focus, family.id, ancestors: 2)

      entries = collect_ancestor_persons(tree.ancestors)

      # No person should be duplicated — partner edges don't create cycles
      assert Enum.all?(entries, &(not &1.duplicated))
    end

    test "no-cycle family — no person is duplicated" do
      family = family_fixture()

      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "married", %{})
      {:ok, _} = Relationships.create_relationship(dad, focus, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})

      tree = PersonGraph.build(focus, family.id, ancestors: 2)

      entries = collect_ancestor_persons(tree.ancestors)
      assert Enum.all?(entries, &(not &1.duplicated))
    end

    test "same person as both parents (bad data) — second entry is duplicated" do
      family = family_fixture()

      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "P"})

      # Create bad data: the same parent appears twice in the parents list.
      # We build a FamilyGraph manually since the DB enforces uniqueness.
      rel = %Ancestry.Relationships.Relationship{
        person_a_id: parent.id,
        person_b_id: focus.id,
        type: "parent"
      }

      graph = %FamilyGraph{
        family_id: family.id,
        people_by_id: %{parent.id => parent, focus.id => focus},
        parents_by_child: %{focus.id => [{parent, rel}, {parent, rel}]},
        children_by_parent: %{parent.id => [focus]},
        partners_by_person: %{}
      }

      tree = PersonGraph.build(focus, graph, ancestors: 1)

      entries = collect_ancestor_persons(tree.ancestors)
      parent_entries = Enum.filter(entries, &(&1.person.id == parent.id))

      # Parent appears twice: once not duplicated, once duplicated
      assert length(parent_entries) == 2
      assert Enum.count(parent_entries, & &1.duplicated) == 1
      assert Enum.count(parent_entries, &(not &1.duplicated)) == 1
    end

    test "self-ancestor (bad data) — stub is duplicated, no stack overflow" do
      family = family_fixture()

      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "F"})

      # Create bad data: person is their own parent.
      # We build a FamilyGraph manually since the DB prevents self-referencing.
      rel = %Ancestry.Relationships.Relationship{
        person_a_id: focus.id,
        person_b_id: focus.id,
        type: "parent"
      }

      graph = %FamilyGraph{
        family_id: family.id,
        people_by_id: %{focus.id => focus},
        parents_by_child: %{focus.id => [{focus, rel}]},
        children_by_parent: %{focus.id => [focus]},
        partners_by_person: %{}
      }

      # Should not stack overflow
      tree = PersonGraph.build(focus, graph, ancestors: 3)

      assert tree.ancestors != nil
      entries = collect_ancestor_persons(tree.ancestors)

      # Focus appears in ancestors as duplicated (already in visited as the focus person)
      focus_entries = Enum.filter(entries, &(&1.person.id == focus.id))
      assert length(focus_entries) >= 1
      assert Enum.any?(focus_entries, & &1.duplicated)
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

      # Build with ancestors: 2 — brother1 is an ex-partner in the center row, NOT an ancestor
      tree = PersonGraph.build(focus, family.id, ancestors: 2)

      entries = collect_ancestor_persons(tree.ancestors)

      # No ancestor should be marked duplicated — Brother1 only appears as an ex-partner
      assert Enum.all?(entries, &(not &1.duplicated))
    end

    test "Type 3: double first cousins — both GP sets appear twice (one duplicated each)" do
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

      tree = PersonGraph.build(focus, family.id, ancestors: 3)

      entries = collect_ancestor_persons(tree.ancestors)

      # Each grandparent from family A and family B appears twice:
      # once not duplicated (first encounter) and once duplicated (second encounter)
      for gp <- [gpa_a, gma_a, gpa_b, gma_b] do
        gp_entries = Enum.filter(entries, &(&1.person.id == gp.id))

        assert length(gp_entries) == 2,
               "Expected #{gp.given_name} to appear exactly twice in ancestor tree"

        assert Enum.count(gp_entries, & &1.duplicated) == 1,
               "Expected #{gp.given_name} to have exactly one duplicated entry"

        assert Enum.count(gp_entries, &(not &1.duplicated)) == 1,
               "Expected #{gp.given_name} to have exactly one non-duplicated entry"
      end
    end

    test "three parents (bad data) — only first two are used, third is silently ignored" do
      family = family_fixture()

      {:ok, parent_a} = People.create_person(family, %{given_name: "ParentA", surname: "P"})
      {:ok, parent_b} = People.create_person(family, %{given_name: "ParentB", surname: "P"})
      {:ok, parent_c} = People.create_person(family, %{given_name: "ParentC", surname: "P"})
      {:ok, focus} = People.create_person(family, %{given_name: "Focus", surname: "P"})

      # Build a FamilyGraph manually with 3 parents for the same child.
      # The DB has a unique constraint on (person_a_id, person_b_id, type), so we
      # construct the graph directly instead of via Relationships.create_relationship.
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

      graph = %FamilyGraph{
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

      tree = PersonGraph.build(focus, graph, ancestors: 1)

      assert tree.ancestors != nil
      # Only the first two parents become the ancestor couple; the third is silently ignored
      assert tree.ancestors.couple.person_a.person.id == parent_a.id
      assert tree.ancestors.couple.person_b.person.id == parent_b.id
    end
  end

  describe "generation renumbering" do
    test "simple 2-gen tree: grandparents=0, parents=1, focus=2" do
      family = family_fixture()

      {:ok, grandparent} =
        People.create_person(family, %{given_name: "Grandparent", surname: "G"})

      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "G"})
      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "G"})

      {:ok, _} =
        Relationships.create_relationship(grandparent, parent, "parent", %{role: "father"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      tree = PersonGraph.build(child, family.id, ancestors: 2)

      assert tree.generations[grandparent.id] == 0
      assert tree.generations[parent.id] == 1
      assert tree.generations[child.id] == 2
    end

    test "with descendants: focus at max_ancestors, children below" do
      family = family_fixture()

      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "G"})
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "G"})
      {:ok, kid} = People.create_person(family, %{given_name: "Kid", surname: "G"})

      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(person, kid, "parent", %{role: "father"})

      tree = PersonGraph.build(person, family.id, ancestors: 1, descendants: 1)

      assert tree.generations[parent.id] == 0
      assert tree.generations[person.id] == 1
      assert tree.generations[kid.id] == 2
    end

    test "asymmetric branches: max depth drives renumbering" do
      family = family_fixture()

      {:ok, paternal_gp} =
        People.create_person(family, %{given_name: "PaternalGP", surname: "G"})

      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "G"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "G"})
      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "G"})

      {:ok, _} = Relationships.create_relationship(paternal_gp, dad, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})

      tree = PersonGraph.build(child, family.id, ancestors: 2)

      assert tree.generations[paternal_gp.id] == 0
      assert tree.generations[dad.id] == 1
      assert tree.generations[mom.id] == 1
      assert tree.generations[child.id] == 2
    end

    test "no ancestors: focus is generation 0" do
      family = family_fixture()

      {:ok, person} = People.create_person(family, %{given_name: "Solo", surname: "G"})

      tree = PersonGraph.build(person, family.id, ancestors: 0)

      assert tree.generations[person.id] == 0
    end
  end

  describe "has_more indicators" do
    test "ancestor at depth boundary shows has_more when more ancestors exist" do
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

      # ancestors: 1 shows parent only; grandparent is beyond the boundary
      tree = PersonGraph.build(child, family.id, ancestors: 1)

      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.person.id == parent.id
      assert tree.ancestors.parent_trees == []
      assert tree.ancestors.has_more == true
    end

    test "ancestor at depth boundary shows has_more false when no more ancestors" do
      family = family_fixture()

      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "L"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "L"})

      # parent has no parents of their own
      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      # ancestors: 1 shows parent; parent has no parents beyond the boundary
      tree = PersonGraph.build(child, family.id, ancestors: 1)

      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.person.id == parent.id
      assert tree.ancestors.parent_trees == []
      assert tree.ancestors.has_more == false
    end
  end

  # --- Test helpers ---

  defp collect_ancestor_persons(nil), do: []

  defp collect_ancestor_persons(%{couple: couple, parent_trees: parent_trees}) do
    persons = [couple.person_a, couple.person_b] |> Enum.reject(&is_nil/1)

    child_persons =
      Enum.flat_map(parent_trees, fn entry -> collect_ancestor_persons(entry.tree) end)

    persons ++ child_persons
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end
end
