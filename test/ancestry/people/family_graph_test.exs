defmodule Ancestry.People.FamilyGraphTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.Relationships

  defp family_with_tree(_context) do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Ancestry.Families.create_family(org, %{name: "Test Family"})

    {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "S"})
    {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "S"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "S"})
    {:ok, partner} = People.create_person(family, %{given_name: "Partner", surname: "S"})

    {:ok, child} =
      People.create_person(family, %{given_name: "Child", surname: "S", birth_year: 2010})

    {:ok, solo_child} =
      People.create_person(family, %{given_name: "Solo", surname: "S", birth_year: 2015})

    {:ok, ex} = People.create_person(family, %{given_name: "Ex", surname: "S"})

    {:ok, _} = Relationships.create_relationship(grandpa, parent, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(grandma, parent, "parent", %{role: "mother"})

    {:ok, _} =
      Relationships.create_relationship(parent, partner, "married", %{marriage_year: 2005})

    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(partner, child, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(parent, solo_child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent, ex, "divorced", %{})

    %{
      family: family,
      grandpa: grandpa,
      grandma: grandma,
      parent: parent,
      partner: partner,
      child: child,
      solo_child: solo_child,
      ex: ex
    }
  end

  describe "for_family/1" do
    setup :family_with_tree

    test "emits exactly 2 DB queries", %{family: family} do
      :telemetry.attach(
        "test-query-count",
        [:ancestry, :repo, :query],
        fn _, _, _, _ ->
          send(self(), :query_fired)
        end,
        nil
      )

      _graph = FamilyGraph.for_family(family.id)

      :telemetry.detach("test-query-count")

      count = count_messages(:query_fired)
      assert count == 2, "Expected 2 queries, got #{count}"
    end

    test "people_by_id contains all family members", %{family: family} do
      graph = FamilyGraph.for_family(family.id)
      assert map_size(graph.people_by_id) == 7
    end

    test "parents_by_child indexes parent relationships only", %{
      family: family,
      parent: parent,
      grandpa: grandpa,
      grandma: grandma
    } do
      graph = FamilyGraph.for_family(family.id)

      parent_entries = Map.get(graph.parents_by_child, parent.id, [])
      parent_ids = Enum.map(parent_entries, fn {p, _r} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(parent_ids, MapSet.new([grandpa.id, grandma.id]))
    end

    test "children_by_parent sorted by birth_year nulls last", %{
      family: family,
      parent: parent,
      child: child,
      solo_child: solo_child
    } do
      graph = FamilyGraph.for_family(family.id)

      children = Map.get(graph.children_by_parent, parent.id, [])
      child_ids = Enum.map(children, & &1.id)
      assert child_ids == [child.id, solo_child.id]
    end

    test "partners_by_person is bidirectional", %{
      family: family,
      parent: parent,
      partner: partner
    } do
      graph = FamilyGraph.for_family(family.id)

      from_parent = Map.get(graph.partners_by_person, parent.id, [])
      from_partner = Map.get(graph.partners_by_person, partner.id, [])

      assert Enum.any?(from_parent, fn {p, _} -> p.id == partner.id end)
      assert Enum.any?(from_partner, fn {p, _} -> p.id == parent.id end)
    end
  end

  defp count_messages(msg) do
    receive do
      ^msg -> 1 + count_messages(msg)
    after
      0 -> 0
    end
  end
end
