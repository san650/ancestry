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
      test_pid = self()
      handler_id = "test-query-count-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:ancestry, :repo, :query],
        fn _, _, _, pid ->
          if self() == pid do
            send(pid, :query_fired)
          end
        end,
        test_pid
      )

      _graph = FamilyGraph.for_family(family.id)

      :telemetry.detach(handler_id)

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

  describe "lookup parity with Ancestry.Relationships" do
    setup :family_with_tree

    test "active_partners matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.active_partners(graph, parent.id)
      sql_result = Relationships.get_active_partners(parent.id, family_id: family.id)

      graph_ids = Enum.map(graph_result, fn {p, _} -> p.id end) |> MapSet.new()
      sql_ids = Enum.map(sql_result, fn {p, _} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(graph_ids, sql_ids)
    end

    test "former_partners matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.former_partners(graph, parent.id)
      sql_result = Relationships.get_former_partners(parent.id, family_id: family.id)

      graph_ids = Enum.map(graph_result, fn {p, _} -> p.id end) |> MapSet.new()
      sql_ids = Enum.map(sql_result, fn {p, _} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(graph_ids, sql_ids)
    end

    test "parents matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.parents(graph, parent.id)
      sql_result = Relationships.get_parents(parent.id, family_id: family.id)

      graph_ids = Enum.map(graph_result, fn {p, _} -> p.id end) |> MapSet.new()
      sql_ids = Enum.map(sql_result, fn {p, _} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(graph_ids, sql_ids)
    end

    test "children matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.children(graph, parent.id)
      sql_result = Relationships.get_children(parent.id, family_id: family.id)

      assert Enum.map(graph_result, & &1.id) == Enum.map(sql_result, & &1.id)
    end

    test "children_of_pair matches SQL", %{family: family, parent: parent, partner: partner} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.children_of_pair(graph, parent.id, partner.id)
      sql_result = Relationships.get_children_of_pair(parent.id, partner.id, family_id: family.id)

      assert Enum.map(graph_result, & &1.id) == Enum.map(sql_result, & &1.id)
    end

    test "solo_children matches SQL", %{family: family, parent: parent, child: child} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.solo_children(graph, parent.id)
      sql_result = Relationships.get_solo_children(parent.id, family_id: family.id)

      assert Enum.map(graph_result, & &1.id) == Enum.map(sql_result, & &1.id)

      # Negative case: child with TWO parents must NOT appear in solo_children
      refute Enum.any?(graph_result, fn p -> p.id == child.id end)
    end

    test "has_children? returns true for a parent", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.has_children?(graph, parent.id)
    end

    test "has_children? returns false for a childless person", %{family: family, child: child} do
      graph = FamilyGraph.for_family(family.id)
      refute FamilyGraph.has_children?(graph, child.id)
    end

    test "fetch_person! returns the person", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.fetch_person!(graph, parent.id).id == parent.id
    end

    test "all_partners returns active + former combined", %{
      family: family,
      parent: parent,
      partner: partner,
      ex: ex
    } do
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

    test "partner_relationship returns relationship between partners", %{
      family: family,
      parent: parent,
      partner: partner
    } do
      graph = FamilyGraph.for_family(family.id)

      rel = FamilyGraph.partner_relationship(graph, parent.id, partner.id)
      assert rel != nil
      assert rel.type == "married"
    end

    test "partner_relationship returns nil for non-partners", %{
      family: family,
      parent: parent,
      grandpa: grandpa
    } do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.partner_relationship(graph, parent.id, grandpa.id) == nil
    end

    test "partner_relationship is bidirectional", %{
      family: family,
      parent: parent,
      partner: partner
    } do
      graph = FamilyGraph.for_family(family.id)

      assert FamilyGraph.partner_relationship(graph, parent.id, partner.id) != nil
      assert FamilyGraph.partner_relationship(graph, partner.id, parent.id) != nil
    end
  end

  describe "family scoping" do
    test "relationships crossing family boundary are excluded" do
      {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Scoping Org"})
      {:ok, family1} = Ancestry.Families.create_family(org, %{name: "Family 1"})
      {:ok, family2} = Ancestry.Families.create_family(org, %{name: "Family 2"})

      {:ok, person} = People.create_person(family1, %{given_name: "Shared", surname: "S"})
      People.add_to_family(person, family2)

      {:ok, outsider} = People.create_person(family2, %{given_name: "Outsider", surname: "S"})
      {:ok, _} = Relationships.create_relationship(outsider, person, "parent", %{role: "father"})

      graph = FamilyGraph.for_family(family1.id)

      # outsider is not in family1, so the parent relationship is excluded
      assert FamilyGraph.parents(graph, person.id) == []
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
