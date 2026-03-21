defmodule Ancestry.KinshipTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship
  alias Ancestry.People
  alias Ancestry.Relationships

  # Helper to create an org
  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    org
  end

  # Helper to create a family and return it
  defp family_fixture(attrs \\ %{}) do
    org = org_fixture()

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end

  # Helper to create a person within a family
  defp person_fixture(family, attrs) do
    {:ok, person} = People.create_person(family, attrs)
    person
  end

  # Helper to create a parent relationship
  defp make_parent!(parent, child, role) do
    {:ok, _rel} = Relationships.create_relationship(parent, child, "parent", %{role: role})
    :ok
  end

  describe "calculate/2 - error cases" do
    test "returns error when both IDs are the same" do
      family = family_fixture()
      person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})

      assert {:error, :same_person} = Kinship.calculate(person.id, person.id)
    end

    test "returns error when no common ancestor is found" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "Jones"})

      assert {:error, :no_common_ancestor} = Kinship.calculate(alice.id, bob.id)
    end
  end

  describe "calculate/2 - parent/child" do
    setup do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      make_parent!(grandpa, parent, "father")
      make_parent!(parent, child, "father")

      %{family: family, grandpa: grandpa, parent: parent, child: child}
    end

    test "parent to child (downward)", %{parent: parent, child: child} do
      assert {:ok, result} = Kinship.calculate(parent.id, child.id)

      assert result.relationship == "Parent"
      assert result.steps_a == 0
      assert result.steps_b == 1
      assert result.half? == false

      # MRCA should be the parent themselves
      assert result.mrca.id == parent.id

      # Path: parent (Self) -> child
      assert length(result.path) == 2
      assert Enum.at(result.path, 0).label == "Self"
      assert Enum.at(result.path, 0).person.id == parent.id
      assert Enum.at(result.path, 1).label == "Child"
      assert Enum.at(result.path, 1).person.id == child.id
    end

    test "child to parent (upward)", %{parent: parent, child: child} do
      assert {:ok, result} = Kinship.calculate(child.id, parent.id)

      assert result.relationship == "Child"
      assert result.steps_a == 1
      assert result.steps_b == 0
      assert result.half? == false

      # MRCA should be the parent (person B)
      assert result.mrca.id == parent.id

      # Path: child (Self) -> parent
      assert length(result.path) == 2
      assert Enum.at(result.path, 0).label == "Self"
      assert Enum.at(result.path, 0).person.id == child.id
      assert Enum.at(result.path, 1).label == "Parent"
      assert Enum.at(result.path, 1).person.id == parent.id
    end
  end

  describe "calculate/2 - grandparent/grandchild" do
    setup do
      family = family_fixture()
      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      grandchild = person_fixture(family, %{given_name: "Grandchild", surname: "Smith"})

      make_parent!(grandparent, parent, "father")
      make_parent!(parent, grandchild, "father")

      %{family: family, grandparent: grandparent, parent: parent, grandchild: grandchild}
    end

    test "grandparent to grandchild", %{grandparent: grandparent, grandchild: grandchild} do
      assert {:ok, result} = Kinship.calculate(grandparent.id, grandchild.id)

      assert result.relationship == "Grandparent"
      assert result.steps_a == 0
      assert result.steps_b == 2
      assert result.half? == false
      assert result.mrca.id == grandparent.id

      assert length(result.path) == 3
      assert Enum.at(result.path, 0).label == "Self"
      assert Enum.at(result.path, 1).label == "Child"
      assert Enum.at(result.path, 2).label == "Grandchild"
    end

    test "grandchild to grandparent", %{grandparent: grandparent, grandchild: grandchild} do
      assert {:ok, result} = Kinship.calculate(grandchild.id, grandparent.id)

      assert result.relationship == "Grandchild"
      assert result.steps_a == 2
      assert result.steps_b == 0
      assert result.half? == false
      assert result.mrca.id == grandparent.id

      assert length(result.path) == 3
      assert Enum.at(result.path, 0).label == "Self"
      assert Enum.at(result.path, 1).label == "Parent"
      assert Enum.at(result.path, 2).label == "Grandparent"
    end
  end

  describe "calculate/2 - great-grandparent" do
    setup do
      family = family_fixture()
      great_gp = person_fixture(family, %{given_name: "GreatGP", surname: "Smith"})
      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      make_parent!(great_gp, grandparent, "father")
      make_parent!(grandparent, parent, "father")
      make_parent!(parent, child, "father")

      %{family: family, great_gp: great_gp, child: child}
    end

    test "great-grandparent to great-grandchild", %{great_gp: great_gp, child: child} do
      assert {:ok, result} = Kinship.calculate(great_gp.id, child.id)

      assert result.relationship == "Great Grandparent"
      assert result.steps_a == 0
      assert result.steps_b == 3
      assert result.half? == false
      assert result.mrca.id == great_gp.id
    end

    test "great-grandchild to great-grandparent", %{great_gp: great_gp, child: child} do
      assert {:ok, result} = Kinship.calculate(child.id, great_gp.id)

      assert result.relationship == "Great Grandchild"
      assert result.steps_a == 3
      assert result.steps_b == 0
      assert result.half? == false
    end
  end

  describe "calculate/2 - siblings" do
    test "full siblings (share both parents)" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Dad", surname: "Smith"})
      mother = person_fixture(family, %{given_name: "Mom", surname: "Smith"})
      sibling_a = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      sibling_b = person_fixture(family, %{given_name: "Bob", surname: "Smith"})

      make_parent!(father, sibling_a, "father")
      make_parent!(mother, sibling_a, "mother")
      make_parent!(father, sibling_b, "father")
      make_parent!(mother, sibling_b, "mother")

      assert {:ok, result} = Kinship.calculate(sibling_a.id, sibling_b.id)

      assert result.relationship == "Sibling"
      assert result.steps_a == 1
      assert result.steps_b == 1
      assert result.half? == false
    end
  end

  describe "calculate/2 - half-siblings" do
    test "half-siblings (share one parent)" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Dad", surname: "Smith"})
      mother1 = person_fixture(family, %{given_name: "Mom1", surname: "Smith"})
      mother2 = person_fixture(family, %{given_name: "Mom2", surname: "Jones"})
      child1 = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      child2 = person_fixture(family, %{given_name: "Bob", surname: "Smith"})

      make_parent!(father, child1, "father")
      make_parent!(mother1, child1, "mother")
      make_parent!(father, child2, "father")
      make_parent!(mother2, child2, "mother")

      assert {:ok, result} = Kinship.calculate(child1.id, child2.id)

      assert result.relationship == "Half-Sibling"
      assert result.steps_a == 1
      assert result.steps_b == 1
      assert result.half? == true
      assert result.mrca.id == father.id
    end
  end

  describe "calculate/2 - aunt/uncle and niece/nephew" do
    setup do
      family = family_fixture()
      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      grandma = person_fixture(family, %{given_name: "Grandma", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      uncle = person_fixture(family, %{given_name: "Uncle", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      make_parent!(grandparent, parent, "father")
      make_parent!(grandma, parent, "mother")
      make_parent!(grandparent, uncle, "father")
      make_parent!(grandma, uncle, "mother")
      make_parent!(parent, child, "father")

      %{
        family: family,
        grandparent: grandparent,
        grandma: grandma,
        parent: parent,
        uncle: uncle,
        child: child
      }
    end

    test "uncle to niece/nephew", %{uncle: uncle, child: child} do
      assert {:ok, result} = Kinship.calculate(uncle.id, child.id)

      assert result.relationship == "Uncle & Aunt"
      assert result.steps_a == 1
      assert result.steps_b == 2
      assert result.half? == false
    end

    test "niece/nephew to uncle", %{uncle: uncle, child: child} do
      assert {:ok, result} = Kinship.calculate(child.id, uncle.id)

      assert result.relationship == "Nephew & Niece"
      assert result.steps_a == 2
      assert result.steps_b == 1
      assert result.half? == false
    end
  end

  describe "calculate/2 - first cousins" do
    setup do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      grandma = person_fixture(family, %{given_name: "Grandma", surname: "Smith"})
      parent_a = person_fixture(family, %{given_name: "ParentA", surname: "Smith"})
      parent_b = person_fixture(family, %{given_name: "ParentB", surname: "Smith"})
      cousin_a = person_fixture(family, %{given_name: "CousinA", surname: "Smith"})
      cousin_b = person_fixture(family, %{given_name: "CousinB", surname: "Smith"})

      make_parent!(grandpa, parent_a, "father")
      make_parent!(grandma, parent_a, "mother")
      make_parent!(grandpa, parent_b, "father")
      make_parent!(grandma, parent_b, "mother")
      make_parent!(parent_a, cousin_a, "father")
      make_parent!(parent_b, cousin_b, "father")

      %{
        family: family,
        grandpa: grandpa,
        cousin_a: cousin_a,
        cousin_b: cousin_b
      }
    end

    test "first cousins", %{cousin_a: cousin_a, cousin_b: cousin_b} do
      assert {:ok, result} = Kinship.calculate(cousin_a.id, cousin_b.id)

      assert result.relationship == "First Cousin"
      assert result.steps_a == 2
      assert result.steps_b == 2
      assert result.half? == false
    end
  end

  describe "calculate/2 - second cousins" do
    setup do
      family = family_fixture()
      great_gp = person_fixture(family, %{given_name: "GreatGP", surname: "Smith"})
      great_gm = person_fixture(family, %{given_name: "GreatGM", surname: "Smith"})
      gp_a = person_fixture(family, %{given_name: "GPA", surname: "Smith"})
      gp_b = person_fixture(family, %{given_name: "GPB", surname: "Smith"})
      parent_a = person_fixture(family, %{given_name: "ParentA", surname: "Smith"})
      parent_b = person_fixture(family, %{given_name: "ParentB", surname: "Smith"})
      cousin_a = person_fixture(family, %{given_name: "CousinA", surname: "Smith"})
      cousin_b = person_fixture(family, %{given_name: "CousinB", surname: "Smith"})

      make_parent!(great_gp, gp_a, "father")
      make_parent!(great_gm, gp_a, "mother")
      make_parent!(great_gp, gp_b, "father")
      make_parent!(great_gm, gp_b, "mother")
      make_parent!(gp_a, parent_a, "father")
      make_parent!(gp_b, parent_b, "father")
      make_parent!(parent_a, cousin_a, "father")
      make_parent!(parent_b, cousin_b, "father")

      %{family: family, cousin_a: cousin_a, cousin_b: cousin_b}
    end

    test "second cousins", %{cousin_a: cousin_a, cousin_b: cousin_b} do
      assert {:ok, result} = Kinship.calculate(cousin_a.id, cousin_b.id)

      assert result.relationship == "Second Cousin"
      assert result.steps_a == 3
      assert result.steps_b == 3
      assert result.half? == false
    end
  end

  describe "calculate/2 - great uncle & aunt" do
    setup do
      family = family_fixture()
      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      grandma = person_fixture(family, %{given_name: "Grandma", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})

      sibling_of_grandparent =
        person_fixture(family, %{given_name: "GreatUncle", surname: "Smith"})

      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      # grandparent and sibling_of_grandparent are full siblings
      great_gp_father = person_fixture(family, %{given_name: "GreatGPFather", surname: "Smith"})
      great_gp_mother = person_fixture(family, %{given_name: "GreatGPMother", surname: "Smith"})

      make_parent!(great_gp_father, grandparent, "father")
      make_parent!(great_gp_mother, grandparent, "mother")
      make_parent!(great_gp_father, sibling_of_grandparent, "father")
      make_parent!(great_gp_mother, sibling_of_grandparent, "mother")
      make_parent!(grandparent, parent, "father")
      make_parent!(grandma, parent, "mother")
      make_parent!(parent, child, "father")

      %{
        family: family,
        sibling_of_grandparent: sibling_of_grandparent,
        child: child
      }
    end

    test "sibling of grandparent to child is Great Uncle & Aunt", %{
      sibling_of_grandparent: sibling_of_grandparent,
      child: child
    } do
      assert {:ok, result} = Kinship.calculate(sibling_of_grandparent.id, child.id)

      assert result.relationship == "Great Uncle & Aunt"
      assert result.steps_a == 1
      assert result.steps_b == 3
      assert result.half? == false
    end

    test "child to sibling of grandparent is Grand Nephew & Niece", %{
      sibling_of_grandparent: sibling_of_grandparent,
      child: child
    } do
      assert {:ok, result} = Kinship.calculate(child.id, sibling_of_grandparent.id)

      assert result.relationship == "Grand Nephew & Niece"
      assert result.steps_a == 3
      assert result.steps_b == 1
      assert result.half? == false
    end
  end

  describe "calculate/2 - great grand uncle & aunt" do
    setup do
      family = family_fixture()

      # Create shared parents for great-grandparent and their sibling
      gg_gp_father = person_fixture(family, %{given_name: "GGGPFather", surname: "Smith"})
      gg_gp_mother = person_fixture(family, %{given_name: "GGGPMother", surname: "Smith"})

      great_grandparent = person_fixture(family, %{given_name: "GreatGrandpa", surname: "Smith"})

      sibling_of_great_grandparent =
        person_fixture(family, %{given_name: "GreatGrandUncle", surname: "Smith"})

      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      # great_grandparent and sibling_of_great_grandparent are full siblings
      make_parent!(gg_gp_father, great_grandparent, "father")
      make_parent!(gg_gp_mother, great_grandparent, "mother")
      make_parent!(gg_gp_father, sibling_of_great_grandparent, "father")
      make_parent!(gg_gp_mother, sibling_of_great_grandparent, "mother")

      make_parent!(great_grandparent, grandparent, "father")
      make_parent!(grandparent, parent, "father")
      make_parent!(parent, child, "father")

      %{
        family: family,
        sibling_of_great_grandparent: sibling_of_great_grandparent,
        child: child
      }
    end

    test "sibling of great-grandparent to child is Great Grand Uncle & Aunt", %{
      sibling_of_great_grandparent: sibling_of_great_grandparent,
      child: child
    } do
      assert {:ok, result} = Kinship.calculate(sibling_of_great_grandparent.id, child.id)

      assert result.relationship == "Great Grand Uncle & Aunt"
      assert result.steps_a == 1
      assert result.steps_b == 4
      assert result.half? == false
    end

    test "child to sibling of great-grandparent is Great Grand Nephew & Niece", %{
      sibling_of_great_grandparent: sibling_of_great_grandparent,
      child: child
    } do
      assert {:ok, result} = Kinship.calculate(child.id, sibling_of_great_grandparent.id)

      assert result.relationship == "Great Grand Nephew & Niece"
      assert result.steps_a == 4
      assert result.steps_b == 1
      assert result.half? == false
    end
  end

  describe "calculate/2 - deep ancestor naming (3rd great grandparent)" do
    setup do
      family = family_fixture()
      # 6 generations: 3rd-great-gp -> 2nd-great-gp -> great-gp -> grandparent -> parent -> child
      third_great_gp = person_fixture(family, %{given_name: "3rdGreatGP", surname: "Smith"})
      second_great_gp = person_fixture(family, %{given_name: "2ndGreatGP", surname: "Smith"})
      great_gp = person_fixture(family, %{given_name: "GreatGP", surname: "Smith"})
      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      make_parent!(third_great_gp, second_great_gp, "father")
      make_parent!(second_great_gp, great_gp, "father")
      make_parent!(great_gp, grandparent, "father")
      make_parent!(grandparent, parent, "father")
      make_parent!(parent, child, "father")

      %{family: family, third_great_gp: third_great_gp, child: child}
    end

    test "3rd great grandparent to child", %{third_great_gp: third_great_gp, child: child} do
      assert {:ok, result} = Kinship.calculate(third_great_gp.id, child.id)

      assert result.relationship == "3rd Great Grandparent"
      assert result.steps_a == 0
      assert result.steps_b == 5
      assert result.half? == false
      assert result.mrca.id == third_great_gp.id
    end

    test "child to 3rd great grandparent", %{third_great_gp: third_great_gp, child: child} do
      assert {:ok, result} = Kinship.calculate(child.id, third_great_gp.id)

      assert result.relationship == "3rd Great Grandchild"
      assert result.steps_a == 5
      assert result.steps_b == 0
      assert result.half? == false
      assert result.mrca.id == third_great_gp.id
    end
  end

  describe "calculate/2 - first cousin once removed" do
    setup do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      grandma = person_fixture(family, %{given_name: "Grandma", surname: "Smith"})
      parent_a = person_fixture(family, %{given_name: "ParentA", surname: "Smith"})
      parent_b = person_fixture(family, %{given_name: "ParentB", surname: "Smith"})
      cousin = person_fixture(family, %{given_name: "Cousin", surname: "Smith"})
      child_of_cousin = person_fixture(family, %{given_name: "ChildOfCousin", surname: "Smith"})

      make_parent!(grandpa, parent_a, "father")
      make_parent!(grandma, parent_a, "mother")
      make_parent!(grandpa, parent_b, "father")
      make_parent!(grandma, parent_b, "mother")
      # cousin is child of parent_a (2 steps from grandpa)
      make_parent!(parent_a, cousin, "father")
      # child_of_cousin is child of parent_b (2 steps from grandpa)
      make_parent!(parent_b, child_of_cousin, "father")

      # Add one more generation: child_of_cousin_b is child of child_of_cousin (3 steps from grandpa)
      # So cousin (2 steps) vs child_of_cousin_b (3 steps) = first cousin once removed
      child_of_cousin_b =
        person_fixture(family, %{given_name: "ChildOfCousinB", surname: "Smith"})

      make_parent!(child_of_cousin, child_of_cousin_b, "father")

      %{
        family: family,
        cousin: cousin,
        child_of_cousin_b: child_of_cousin_b
      }
    end

    test "first cousin once removed", %{cousin: cousin, child_of_cousin_b: child_of_cousin_b} do
      assert {:ok, result} = Kinship.calculate(cousin.id, child_of_cousin_b.id)

      assert result.relationship == "First Cousin, Once Removed"
      assert result.steps_a == 2
      assert result.steps_b == 3
      assert result.half? == false
    end
  end

  describe "calculate/2 - path reconstruction" do
    test "path for parent-child includes correct labels" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      make_parent!(parent, child, "father")

      assert {:ok, result} = Kinship.calculate(parent.id, child.id)

      path_labels = Enum.map(result.path, & &1.label)
      assert path_labels == ["Self", "Child"]
    end

    test "path for siblings includes correct labels" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Dad", surname: "Smith"})
      mother = person_fixture(family, %{given_name: "Mom", surname: "Smith"})
      alice = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "Smith"})

      make_parent!(father, alice, "father")
      make_parent!(mother, alice, "mother")
      make_parent!(father, bob, "father")
      make_parent!(mother, bob, "mother")

      assert {:ok, result} = Kinship.calculate(alice.id, bob.id)

      path_labels = Enum.map(result.path, & &1.label)
      assert path_labels == ["Self", "Parent", "Sibling"]
    end

    test "path for grandchild to grandparent" do
      family = family_fixture()
      grandparent = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      grandchild = person_fixture(family, %{given_name: "Grandchild", surname: "Smith"})

      make_parent!(grandparent, parent, "father")
      make_parent!(parent, grandchild, "father")

      assert {:ok, result} = Kinship.calculate(grandchild.id, grandparent.id)

      path_labels = Enum.map(result.path, & &1.label)
      assert path_labels == ["Self", "Parent", "Grandparent"]
    end

    test "path for second cousins includes correct intermediate labels" do
      family = family_fixture()
      great_gp = person_fixture(family, %{given_name: "GreatGP", surname: "Smith"})
      great_gm = person_fixture(family, %{given_name: "GreatGM", surname: "Smith"})
      gp_a = person_fixture(family, %{given_name: "GPA", surname: "Smith"})
      gp_b = person_fixture(family, %{given_name: "GPB", surname: "Smith"})
      parent_a = person_fixture(family, %{given_name: "ParentA", surname: "Smith"})
      parent_b = person_fixture(family, %{given_name: "ParentB", surname: "Smith"})
      cousin_a = person_fixture(family, %{given_name: "CousinA", surname: "Smith"})
      cousin_b = person_fixture(family, %{given_name: "CousinB", surname: "Smith"})

      make_parent!(great_gp, gp_a, "father")
      make_parent!(great_gm, gp_a, "mother")
      make_parent!(great_gp, gp_b, "father")
      make_parent!(great_gm, gp_b, "mother")
      make_parent!(gp_a, parent_a, "father")
      make_parent!(gp_b, parent_b, "father")
      make_parent!(parent_a, cousin_a, "father")
      make_parent!(parent_b, cousin_b, "father")

      assert {:ok, result} = Kinship.calculate(cousin_a.id, cousin_b.id)

      path_labels = Enum.map(result.path, & &1.label)

      # CousinA (Self) -> ParentA (Parent) -> GPA (Grandparent) -> GreatGP (Great Grandparent)
      #   -> GPB (Great Uncle & Aunt) -> ParentB (First Cousin, Once Removed) -> CousinB (Second Cousin)
      assert path_labels == [
               "Self",
               "Parent",
               "Grandparent",
               "Great Grandparent",
               "Great Uncle & Aunt",
               "First Cousin, Once Removed",
               "Second Cousin"
             ]
    end

    test "path for first cousins" do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      grandma = person_fixture(family, %{given_name: "Grandma", surname: "Smith"})
      parent_a = person_fixture(family, %{given_name: "ParentA", surname: "Smith"})
      parent_b = person_fixture(family, %{given_name: "ParentB", surname: "Smith"})
      cousin_a = person_fixture(family, %{given_name: "CousinA", surname: "Smith"})
      cousin_b = person_fixture(family, %{given_name: "CousinB", surname: "Smith"})

      make_parent!(grandpa, parent_a, "father")
      make_parent!(grandma, parent_a, "mother")
      make_parent!(grandpa, parent_b, "father")
      make_parent!(grandma, parent_b, "mother")
      make_parent!(parent_a, cousin_a, "father")
      make_parent!(parent_b, cousin_b, "father")

      assert {:ok, result} = Kinship.calculate(cousin_a.id, cousin_b.id)

      path_labels = Enum.map(result.path, & &1.label)
      assert path_labels == ["Self", "Parent", "Grandparent", "Uncle & Aunt", "First Cousin"]
    end
  end

  describe "calculate/2 - half-cousins" do
    test "half-first cousins (share only one grandparent)" do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "Smith"})
      grandma1 = person_fixture(family, %{given_name: "Grandma1", surname: "Smith"})
      grandma2 = person_fixture(family, %{given_name: "Grandma2", surname: "Jones"})
      parent_a = person_fixture(family, %{given_name: "ParentA", surname: "Smith"})
      parent_b = person_fixture(family, %{given_name: "ParentB", surname: "Smith"})
      cousin_a = person_fixture(family, %{given_name: "CousinA", surname: "Smith"})
      cousin_b = person_fixture(family, %{given_name: "CousinB", surname: "Smith"})

      # parent_a has grandpa + grandma1
      make_parent!(grandpa, parent_a, "father")
      make_parent!(grandma1, parent_a, "mother")
      # parent_b has grandpa + grandma2 (different mother = half-siblings)
      make_parent!(grandpa, parent_b, "father")
      make_parent!(grandma2, parent_b, "mother")
      make_parent!(parent_a, cousin_a, "father")
      make_parent!(parent_b, cousin_b, "father")

      assert {:ok, result} = Kinship.calculate(cousin_a.id, cousin_b.id)

      assert result.relationship == "Half-First Cousin"
      assert result.steps_a == 2
      assert result.steps_b == 2
      assert result.half? == true
      assert result.mrca.id == grandpa.id
    end
  end

  describe "dna_percentage/3" do
    test "parent/child: 50%" do
      assert Kinship.dna_percentage(0, 1, false) == 50.0
    end

    test "siblings: 50%" do
      assert Kinship.dna_percentage(1, 1, false) == 50.0
    end

    test "grandparent: 25%" do
      assert Kinship.dna_percentage(0, 2, false) == 25.0
    end

    test "uncle/aunt: 25%" do
      assert Kinship.dna_percentage(1, 2, false) == 25.0
    end

    test "1st cousin: 12.5%" do
      assert Kinship.dna_percentage(2, 2, false) == 12.5
    end

    test "1st cousin once removed: 6.25%" do
      assert Kinship.dna_percentage(2, 3, false) == 6.25
    end

    test "2nd cousin: 3.125%" do
      assert Kinship.dna_percentage(3, 3, false) == 3.125
    end

    test "half-sibling: 25%" do
      assert Kinship.dna_percentage(1, 1, true) == 25.0
    end

    test "half-first cousin: 6.25%" do
      assert Kinship.dna_percentage(2, 2, true) == 6.25
    end
  end

  describe "calculate/2 - Kinship struct" do
    test "returns a proper Kinship struct" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})

      make_parent!(parent, child, "father")

      assert {:ok, %Kinship{} = result} = Kinship.calculate(parent.id, child.id)

      assert is_binary(result.relationship)
      assert is_integer(result.steps_a)
      assert is_integer(result.steps_b)
      assert is_list(result.path)
      assert is_boolean(result.half?)
      assert result.mrca != nil
    end
  end
end
