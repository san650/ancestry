defmodule Ancestry.Kinship.InLawTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.InLaw
  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
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

  describe "calculate/3 - direct spouse" do
    test "returns spouse for married couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      graph = FamilyGraph.for_family(family.id)

      # Label describes what person_a (alice, female) is to person_b
      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id, graph)
      assert result.relationship == "Wife"
      assert result.partner_link == nil
      assert length(result.path) == 2
    end

    test "returns spouse for married couple from B's perspective" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      graph = FamilyGraph.for_family(family.id)

      # Label describes what person_a (bob, male) is to person_b
      assert {:ok, %InLaw{} = result} = InLaw.calculate(bob.id, alice.id, graph)
      assert result.relationship == "Husband"
    end

    test "returns spouse for divorced couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob, "divorced")

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{}} = InLaw.calculate(alice.id, bob.id, graph)
    end

    test "returns spouse for relationship-type couple" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob, "relationship")

      graph = FamilyGraph.for_family(family.id)

      # alice (female) is the "Wife" / "Spouse" from her perspective
      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id, graph)
      assert result.relationship == "Wife"
    end

    test "path has both people" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})
      make_partner!(alice, bob)

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(alice.id, bob.id, graph)
      [node_a, node_b] = result.path
      assert node_a.person.id == alice.id
      assert node_b.person.id == bob.id
      assert node_a.partner_link? == false
      assert node_b.partner_link? == false
    end
  end

  describe "calculate/3 - parent-in-law" do
    test "spouse's parent is parent-in-law (B side hop)" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id, graph)
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

      graph = FamilyGraph.for_family(family.id)

      # wife (female) is the "child-in-law" of father — gendered as Daughter-in-law
      assert {:ok, %InLaw{} = result} = InLaw.calculate(wife.id, father.id, graph)
      assert result.relationship == "Daughter-in-law"
    end

    test "mother-in-law (female parent)" do
      family = family_fixture()
      mother = person_fixture(family, %{given_name: "Mother", surname: "S", gender: "female"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(mother, son)
      make_partner!(son, wife)

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(mother.id, wife.id, graph)
      assert result.relationship == "Mother-in-law"
    end
  end

  describe "calculate/3 - sibling-in-law" do
    test "spouse's sibling is sibling-in-law" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      daughter = person_fixture(family, %{given_name: "Daughter", surname: "S", gender: "female"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(parent, son)
      make_parent!(parent, daughter)
      make_partner!(son, wife)

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(daughter.id, wife.id, graph)
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

      graph = FamilyGraph.for_family(family.id)

      # brother -> wife_of_sister: B-side hop (sister is wife_of_sister's partner)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(brother.id, wife_of_sister.id, graph)
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

      graph = FamilyGraph.for_family(family.id)

      # person_a -> sibling: A-side hop (partner_of_a is person_a's partner, blood sibling of sibling)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(person_a.id, sibling.id, graph)
      assert result.relationship == "Brother-in-law"
      assert result.partner_link.side == :a
      assert result.partner_link.person.id == partner_of_a.id
    end
  end

  describe "calculate/3 - extended in-law" do
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

      graph = FamilyGraph.for_family(family.id)

      # uncle -> partner: B-side hop (nephew is partner's partner, uncle is nephew's uncle)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(uncle.id, partner.id, graph)
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

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(grandpa.id, partner.id, graph)
      assert result.relationship == "Grandparent-in-law"
    end
  end

  describe "calculate/3 - tiebreaker" do
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

      graph = FamilyGraph.for_family(family.id)

      # parent is in-law of person_a through both partners — active should win
      assert {:ok, %InLaw{} = result} = InLaw.calculate(person_a.id, parent.id, graph)
      assert result.partner_link.person.id == active_partner.id
    end
  end

  describe "calculate/3 - no relationship" do
    test "returns error when no in-law path exists" do
      family = family_fixture()
      alice = person_fixture(family, %{given_name: "Alice", surname: "S", gender: "female"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "S", gender: "male"})

      graph = FamilyGraph.for_family(family.id)

      assert {:error, :no_relationship} = InLaw.calculate(alice.id, bob.id, graph)
    end

    test "returns error when blood-related but no partner hop" do
      family = family_fixture()
      parent = person_fixture(family, %{given_name: "Parent", surname: "S", gender: "male"})
      child = person_fixture(family, %{given_name: "Child", surname: "S", gender: "male"})
      make_parent!(parent, child)

      graph = FamilyGraph.for_family(family.id)

      # They are blood-related, not in-law — InLaw.calculate should find no in-law path
      assert {:error, :no_relationship} = InLaw.calculate(parent.id, child.id, graph)
    end
  end

  describe "calculate/3 - path structure" do
    test "path starts with A and ends with B for B-side hop" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id, graph)
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

      graph = FamilyGraph.for_family(family.id)

      assert {:ok, %InLaw{} = result} = InLaw.calculate(father.id, wife.id, graph)

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

      graph = FamilyGraph.for_family(family.id)

      # brother -> wife: A-side hop (sister is brother's partner)
      assert {:ok, %InLaw{} = result} = InLaw.calculate(brother.id, wife.id, graph)
      assert hd(result.path).person.id == brother.id
      assert List.last(result.path).person.id == wife.id
    end
  end

  describe "calculate/3 - zero DB queries with pre-built graph" do
    test "emits 0 queries when graph is pre-built" do
      family = family_fixture()
      father = person_fixture(family, %{given_name: "Father", surname: "S", gender: "male"})
      son = person_fixture(family, %{given_name: "Son", surname: "S", gender: "male"})
      wife = person_fixture(family, %{given_name: "Wife", surname: "S", gender: "female"})
      make_parent!(father, son)
      make_partner!(son, wife)

      graph = FamilyGraph.for_family(family.id)

      :telemetry.attach(
        "in-law-query-count",
        [:ancestry, :repo, :query],
        fn _, _, _, _ ->
          send(self(), :query_fired)
        end,
        nil
      )

      _result = InLaw.calculate(father.id, wife.id, graph)

      :telemetry.detach("in-law-query-count")

      refute_received :query_fired, "Expected 0 queries but at least one was emitted"
    end
  end

  describe "calculate/3 - family scoping" do
    test "returns :no_relationship when partner hop crosses family boundary" do
      family = family_fixture()
      org = Ancestry.Organizations.get_organization!(family.organization_id)
      {:ok, other_family} = Ancestry.Families.create_family(org, %{name: "Other"})

      person_a = person_fixture(family, %{given_name: "A", surname: "S", gender: "male"})

      partner_of_a =
        person_fixture(family, %{given_name: "PartnerA", surname: "S", gender: "female"})

      make_partner!(person_a, partner_of_a)

      parent = person_fixture(other_family, %{given_name: "Parent", surname: "S", gender: "male"})
      person_b = person_fixture(other_family, %{given_name: "B", surname: "S", gender: "male"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(parent, partner_of_a, "parent", %{
          role: "father"
        })

      {:ok, _} =
        Ancestry.Relationships.create_relationship(parent, person_b, "parent", %{role: "father"})

      People.add_to_family(person_b, family)

      graph = FamilyGraph.for_family(family.id)

      assert {:error, :no_relationship} = InLaw.calculate(person_a.id, person_b.id, graph)
    end
  end
end
