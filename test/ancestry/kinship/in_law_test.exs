defmodule Ancestry.Kinship.InLawTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.InLaw
  alias Ancestry.People
  alias Ancestry.Relationships

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    org
  end

  defp family_fixture do
    org = org_fixture()
    {:ok, family} = Ancestry.Families.create_family(org, %{name: "Test Family"})
    family
  end

  defp person_fixture(family, attrs) do
    {:ok, person} = People.create_person(family, attrs)
    person
  end

  defp make_parent!(parent, child) do
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
  end

  defp make_partner!(a, b, type \\ "married") do
    {:ok, _} = Relationships.create_relationship(a, b, type, %{})
  end

  describe "calculate/2 - direct spouse" do
    test "returns spouse for married couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      # Label describes what person_a (alice, female) is to person_b
      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id)
      assert result.relationship == "Wife"
      assert result.partner_link == nil
      assert length(result.path) == 2
    end

    test "returns spouse for married couple from B's perspective" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      # Label describes what person_a (bob, male) is to person_b
      assert {:ok, %InLaw{} = result} = InLaw.calculate(bob.id, alice.id)
      assert result.relationship == "Husband"
    end

    test "returns spouse for divorced couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob, "divorced")

      assert {:ok, %InLaw{}} = InLaw.calculate(alice.id, bob.id)
    end

    test "returns spouse for relationship-type couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob, "relationship")

      # alice (female) is the "Wife" / "Spouse" from her perspective
      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id)
      assert result.relationship == "Wife"
    end

    test "path has both people" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id)
      [node_a, node_b] = result.path
      assert node_a.person.id == alice.id
      assert node_b.person.id == bob.id
      assert node_a.partner_link? == false
      assert node_b.partner_link? == false
    end
  end

  describe "calculate/2 - parent-in-law" do
    test "spouse's parent is parent-in-law (B side hop)" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id)
      assert result.relationship == "Father-in-law"
      assert result.partner_link.side == :b
      assert result.partner_link.person.id == son.id
    end

    test "reverse: wife calculates her relationship to father-in-law" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      # wife (female) is the "child-in-law" of father — gendered as Daughter-in-law
      assert {:ok, %InLaw{} = result} = InLaw.calculate(wife.id, father.id)
      assert result.relationship == "Daughter-in-law"
    end

    test "mother-in-law (female parent)" do
      family = family_fixture()
      mother = person_fixture(family, %{given_name: "Mother", surname: "S", gender: "female"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(mother, son)
      make_partner!(son, wife)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(mother.id, wife.id)
      assert result.relationship == "Mother-in-law"
    end
  end

  describe "calculate/2 - sibling-in-law" do
    test "spouse's sibling is sibling-in-law" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      daughter = person_fixture(family, %{given_name: "Daughter", surname: "S", gender: "female"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(parent, son)
      make_parent!(parent, daughter)
      make_partner!(son, wife)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(daughter.id, wife.id)
      assert result.relationship == "Sister-in-law"
    end

    test "partner-hop on B side: brother finds wife of sister" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      brother = person_fixture(family, %{given_name: "Brother", surname: "S", gender: "male"})
      sister = person_fixture(family, %{given_name: "Sister", surname: "S", gender: "female"})

      make_parent!(parent, brother)
      make_parent!(parent, sister)

      # sister is married to wife_of_sister
      wife_of_sister =
        person_fixture(family, %{given_name: "WifeOfSister", surname: "S", gender: "female"})

      make_partner!(sister, wife_of_sister)

      # brother -> wife_of_sister: B-side hop (sister is wife_of_sister's partner)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(brother.id, wife_of_sister.id)
      assert result.relationship == "Brother-in-law"
      assert result.partner_link.side == :b
      assert result.partner_link.person.id == sister.id
    end

    test "partner-hop on A side: married person finds blood relatives of their partner" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      sibling = person_fixture(family, %{given_name: "Sibling", surname: "S", gender: "female"})
      person_a = person_fixture(family, %{given_name: "PersonA", surname: "S", gender: "male"})

      partner_of_a =
        person_fixture(family, %{given_name: "PartnerOfA", surname: "S", gender: "female"})

      make_parent!(parent, sibling)
      make_parent!(parent, partner_of_a)
      make_partner!(person_a, partner_of_a)

      # person_a -> sibling: A-side hop (partner_of_a is person_a's partner, blood sibling of sibling)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(person_a.id, sibling.id)
      assert result.relationship == "Brother-in-law"
      assert result.partner_link.side == :a
      assert result.partner_link.person.id == partner_of_a.id
    end
  end

  describe "calculate/2 - extended in-law" do
    test "uncle-in-law via partner hop (B side)" do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "S", gender: "male"})
      uncle = person_fixture(family, %{given_name: "Uncle", surname: "S", gender: "male"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      nephew = person_fixture(family, %{given_name: "Nephew", surname: "S", gender: "male"})
      partner = person_fixture(family, %{given_name: "Partner", surname: "S", gender: "female"})
      # uncle and parent are siblings (children of grandpa)
      # nephew is child of parent (making uncle the actual uncle of nephew)
      make_parent!(grandpa, uncle)
      make_parent!(grandpa, parent)
      make_parent!(parent, nephew)
      make_partner!(nephew, partner)

      # uncle -> partner: B-side hop (nephew is partner's partner, uncle is nephew's uncle)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(uncle.id, partner.id)
      assert result.relationship == "Uncle/Aunt-in-law"
      assert result.partner_link.side == :b
    end

    test "grandparent-in-law (B side hop)" do
      family = family_fixture()
      grandpa = person_fixture(family, %{given_name: "Grandpa", surname: "S", gender: "male"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      child = person_fixture(family, %{given_name: "Child", surname: "S", gender: "male"})
      partner = person_fixture(family, %{given_name: "Partner", surname: "S", gender: "female"})
      make_parent!(grandpa, parent)
      make_parent!(parent, child)
      make_partner!(child, partner)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(grandpa.id, partner.id)
      assert result.relationship == "Grandparent-in-law"
    end
  end

  describe "calculate/2 - tiebreaker: active partner wins" do
    test "prefers active partner (married) over former (divorced)" do
      family = family_fixture()
      person_a = person_fixture(family, %{given_name: "A", surname: "S", gender: "male"})
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})

      # Active partner of person_a
      active_partner =
        person_fixture(family, %{given_name: "Active", surname: "S", gender: "female"})

      # Former partner of person_a
      former_partner =
        person_fixture(family, %{given_name: "Former", surname: "S", gender: "female"})

      make_parent!(parent, active_partner)
      make_parent!(parent, former_partner)
      make_partner!(person_a, active_partner, "married")
      make_partner!(person_a, former_partner, "divorced")

      # parent is in-law of person_a through both partners — active should win
      assert {:ok, %InLaw{} = result} = InLaw.calculate(person_a.id, parent.id)
      assert result.partner_link.person.id == active_partner.id
    end
  end

  describe "calculate/2 - no relationship" do
    test "returns error when no in-law path exists" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})

      assert {:error, :no_relationship} = InLaw.calculate(alice.id, bob.id)
    end

    test "returns error when blood-related but no partner hop" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      child = person_fixture(family, %{given_name: "Child", surname: "S", gender: "male"})
      make_parent!(parent, child)

      # They are blood-related, not in-law — InLaw.calculate should find no in-law path
      assert {:error, :no_relationship} = InLaw.calculate(parent.id, child.id)
    end
  end

  describe "calculate/2 - path structure" do
    test "path starts with A and ends with B for B-side hop" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id)
      assert hd(result.path).person.id == father.id
      assert List.last(result.path).person.id == wife.id
    end

    test "partner nodes are marked partner_link?: true for B-side hop" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id)

      partner_linked = Enum.filter(result.path, & &1.partner_link?)
      partner_ids = Enum.map(partner_linked, & &1.person.id)
      assert son.id in partner_ids
      assert wife.id in partner_ids
    end

    test "path starts with A and ends with B for A-side hop" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      brother = person_fixture(family, %{given_name: "Brother", surname: "S", gender: "male"})
      sister = person_fixture(family, %{given_name: "Sister", surname: "S", gender: "female"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(parent, brother)
      make_parent!(parent, sister)
      make_partner!(sister, wife)

      # brother -> wife: A-side hop (sister is brother's partner)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(brother.id, wife.id)
      assert hd(result.path).person.id == brother.id
      assert List.last(result.path).person.id == wife.id
    end
  end
end
