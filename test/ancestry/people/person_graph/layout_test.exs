defmodule Ancestry.People.PersonGraph.LayoutTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.PersonGraph.Layout
  alias Ancestry.People.PersonGraph.Layout.{Couple, Single, LooseLane}

  describe "compute/2" do
    test "returns an empty triple for an empty state" do
      state = %{entries: %{}, edges: [], visited: %{}, graph: nil, focus_id: nil}
      assert {[], 0, 0} = Layout.compute(state, nil)
    end
  end

  describe "__build_descendant_tree__/2" do
    test "single couple with three children produces couple with three single leaf children" do
      focus = make_person(1, "Focus")
      partner = make_person(2, "Partner")
      c1 = make_person(3, "Child1")
      c2 = make_person(4, "Child2")
      c3 = make_person(5, "Child3")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(partner, 0)
        |> add_entry_helper(c1, -1)
        |> add_entry_helper(c2, -1)
        |> add_entry_helper(c3, -1)
        |> add_couple_edge_helper(1, 2, :current_partner)
        |> add_parent_child_edge_helper(1, 3)
        |> add_parent_child_edge_helper(2, 3)
        |> add_parent_child_edge_helper(1, 4)
        |> add_parent_child_edge_helper(2, 4)
        |> add_parent_child_edge_helper(1, 5)
        |> add_parent_child_edge_helper(2, 5)

      result = Layout.__build_descendant_tree__(state, 1)

      assert %Couple{} = result
      assert result.anchor_a.person.id == 1
      assert result.anchor_b.person.id == 2
      assert length(result.children) == 3
      [ch1, ch2, ch3] = result.children
      assert %Single{anchor: %{person: %{id: 3}}, children: []} = ch1
      assert %Single{anchor: %{person: %{id: 4}}, children: []} = ch2
      assert %Single{anchor: %{person: %{id: 5}}, children: []} = ch3
      assert is_nil(result.loose_lane)
    end

    test "focus with no current partner produces single unit" do
      focus = make_person(1, "Focus")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)

      result = Layout.__build_descendant_tree__(state, 1)

      assert %Single{anchor: %{person: %{id: 1}}, children: []} = result
    end

    test "focus with no children produces empty children list" do
      focus = make_person(1, "Focus")
      partner = make_person(2, "Partner")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(partner, 0)
        |> add_couple_edge_helper(1, 2, :current_partner)

      result = Layout.__build_descendant_tree__(state, 1)

      assert %Couple{children: []} = result
    end

    test "ex partner with children places them in loose lane; primary couple has only current children" do
      focus = make_person(1, "Focus")
      current = make_person(2, "Current")
      ex = make_person(3, "Ex")
      current_kid = make_person(4, "CurrentKid")
      ex_kid = make_person(5, "ExKid")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(current, 0)
        |> add_entry_helper(ex, 0)
        |> add_entry_helper(current_kid, -1)
        |> add_entry_helper(ex_kid, -1)
        |> add_couple_edge_helper(1, 2, :current_partner, "married")
        |> add_couple_edge_helper(1, 3, :previous_partner, "divorced")
        |> add_parent_child_edge_helper(1, 4)
        |> add_parent_child_edge_helper(2, 4)
        |> add_parent_child_edge_helper(1, 5)
        |> add_parent_child_edge_helper(3, 5)

      result = Layout.__build_descendant_tree__(state, 1)

      # Primary unit is the couple with the current partner
      assert %Couple{} = result
      assert result.anchor_a.person.id == 1
      assert result.anchor_b.person.id == 2

      # Primary couple has only the current child
      assert length(result.children) == 1
      [curr_child_unit] = result.children
      assert curr_child_unit.anchor.person.id == 4

      # There is a loose lane
      assert %LooseLane{units: units} = result.loose_lane
      assert length(units) == 1
      [ex_unit] = units
      assert %Single{anchor: %{person: %{id: 3}}} = ex_unit
      assert length(ex_unit.children) == 1
      [ex_kid_unit] = ex_unit.children
      assert ex_kid_unit.anchor.person.id == 5
    end

    test "duplicated child is a leaf with no further descent" do
      focus = make_person(1, "Focus")
      partner = make_person(2, "Partner")
      child = make_person(3, "Child")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(partner, 0)
        |> add_entry_helper(child, -1, duplicated: true)
        |> add_couple_edge_helper(1, 2, :current_partner)
        |> add_parent_child_edge_helper(1, 3)
        |> add_parent_child_edge_helper(2, 3)

      result = Layout.__build_descendant_tree__(state, 1)

      assert %Couple{children: [ch]} = result
      # Duplicated child is a leaf single with no children
      assert %Single{anchor: %{person: %{id: 3}, duplicated: true}, children: []} = ch
      assert is_nil(ch.loose_lane)
    end

    test "solo child (only one parent edge) goes into loose lane" do
      # A solo child is a child where only ONE parent_child edge points to it.
      focus = make_person(1, "Focus")
      partner = make_person(2, "Partner")
      joint_kid = make_person(3, "JointKid")
      solo_kid = make_person(4, "SoloKid")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(partner, 0)
        |> add_entry_helper(joint_kid, -1)
        |> add_entry_helper(solo_kid, -1)
        |> add_couple_edge_helper(1, 2, :current_partner)
        # Joint kid: two parent edges
        |> add_parent_child_edge_helper(1, 3)
        |> add_parent_child_edge_helper(2, 3)
        # Solo kid: only one parent edge (from focus)
        |> add_parent_child_edge_helper(1, 4)

      result = Layout.__build_descendant_tree__(state, 1)

      assert %Couple{} = result
      # Joint kid is a regular child of the primary couple
      assert length(result.children) == 1
      [joint_unit] = result.children
      assert joint_unit.anchor.person.id == 3

      # Solo kid is in the loose lane under a nil-anchor single
      assert %LooseLane{units: [solo_unit]} = result.loose_lane
      assert %Single{anchor: nil, children: [solo_kid_unit]} = solo_unit
      assert solo_kid_unit.anchor.person.id == 4
    end

    test "recursive descent: grandchildren are children of the child unit" do
      focus = make_person(1, "Focus")
      partner = make_person(2, "Partner")
      child = make_person(3, "Child")
      child_partner = make_person(4, "ChildPartner")
      grandchild = make_person(5, "Grandchild")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(partner, 0)
        |> add_entry_helper(child, -1)
        |> add_entry_helper(child_partner, -1)
        |> add_entry_helper(grandchild, -2)
        |> add_couple_edge_helper(1, 2, :current_partner)
        |> add_couple_edge_helper(3, 4, :current_partner)
        |> add_parent_child_edge_helper(1, 3)
        |> add_parent_child_edge_helper(2, 3)
        |> add_parent_child_edge_helper(3, 5)
        |> add_parent_child_edge_helper(4, 5)

      result = Layout.__build_descendant_tree__(state, 1)

      assert %Couple{} = result
      assert length(result.children) == 1
      [child_unit] = result.children
      assert %Couple{} = child_unit
      assert child_unit.anchor_a.person.id == 3
      assert child_unit.anchor_b.person.id == 4
      assert length(child_unit.children) == 1
      [gc_unit] = child_unit.children
      assert gc_unit.anchor.person.id == 5
    end

    test "focus with only previous/ex partners and no current partner produces single with loose lane" do
      focus = make_person(1, "Focus")
      ex = make_person(2, "Ex")
      ex_kid = make_person(3, "ExKid")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(ex, 0)
        |> add_entry_helper(ex_kid, -1)
        |> add_couple_edge_helper(1, 2, :previous_partner, "divorced")
        |> add_parent_child_edge_helper(1, 3)
        |> add_parent_child_edge_helper(2, 3)

      result = Layout.__build_descendant_tree__(state, 1)

      # No current partner → primary unit is a Single
      assert %Single{anchor: %{person: %{id: 1}}} = result
      assert result.children == []
      # Ex and their joint kid are in the loose lane
      assert %LooseLane{units: [ex_unit]} = result.loose_lane
      assert %Single{anchor: %{person: %{id: 2}}, children: [kid_unit]} = ex_unit
      assert kid_unit.anchor.person.id == 3
    end
  end

  # ── Test helpers ──────────────────────────────────────────────────────

  defp make_person(id, name, gender \\ nil) do
    %{
      id: id,
      given_name: name,
      surname: "Test",
      gender: gender,
      deceased: false,
      birth_year: nil,
      death_year: nil,
      photo: nil,
      photo_status: nil
    }
  end

  defp empty_state(focus_id) do
    %{entries: %{}, edges: [], visited: %{}, focus_id: focus_id}
  end

  defp add_entry_helper(state, person, gen, opts \\ []) do
    duplicated = Keyword.get(opts, :duplicated, false)
    focus = Keyword.get(opts, :focus, false)

    entry = %{
      person: person,
      gen: gen,
      duplicated: duplicated,
      has_more_up: false,
      has_more_down: false,
      focus: focus
    }

    entries = Map.update(state.entries, gen, [entry], &(&1 ++ [entry]))
    visited = Map.put(state.visited, person.id, gen)
    %{state | entries: entries, visited: visited}
  end

  defp add_couple_edge_helper(state, a_id, b_id, edge_type, rel_kind \\ "married") do
    edge = %Ancestry.People.GraphEdge{
      type: edge_type,
      relationship_kind: rel_kind,
      from_id: "person-#{a_id}",
      to_id: "person-#{b_id}"
    }

    %{state | edges: state.edges ++ [edge]}
  end

  defp add_parent_child_edge_helper(state, parent_id, child_id) do
    edge = %Ancestry.People.GraphEdge{
      type: :parent_child,
      relationship_kind: "parent",
      from_id: "person-#{parent_id}",
      to_id: "person-#{child_id}"
    }

    %{state | edges: state.edges ++ [edge]}
  end
end
