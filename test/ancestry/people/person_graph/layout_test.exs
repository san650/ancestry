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

  describe "__build_ancestor_tree__/2 (via direct call)" do
    test "focus with no parents returns nil" do
      focus = make_person(1, "Focus")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)

      assert nil == Layout.__build_ancestor_tree__(state, 1)
    end

    test "focus with single parent returns a %Single{}" do
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_parent_child_edge_helper(2, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      assert %Single{} = result
      assert result.anchor.person.id == 2
      assert result.children == []
    end

    test "two-generation symmetric ancestors" do
      # Focus has Father + Mother.
      # Father has Grandpa-pat + Grandma-pat.
      # Mother has Grandpa-mat + Grandma-mat.
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_pat = make_person(4, "Grandpa-pat")
      gm_pat = make_person(5, "Grandma-pat")
      gp_mat = make_person(6, "Grandpa-mat")
      gm_mat = make_person(7, "Grandma-mat")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_pat, 2)
        |> add_entry_helper(gm_pat, 2)
        |> add_entry_helper(gp_mat, 2)
        |> add_entry_helper(gm_mat, 2)
        # Father + Mother are a couple
        |> add_couple_edge_helper(2, 3, :current_partner)
        # Father's parents
        |> add_couple_edge_helper(4, 5, :current_partner)
        |> add_parent_child_edge_helper(4, 2)
        |> add_parent_child_edge_helper(5, 2)
        # Mother's parents
        |> add_couple_edge_helper(6, 7, :current_partner)
        |> add_parent_child_edge_helper(6, 3)
        |> add_parent_child_edge_helper(7, 3)
        # Focus's parents
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      # Top-level: Father+Mother couple
      assert %Couple{} = result
      assert result.anchor_a.person.id == 2
      assert result.anchor_b.person.id == 3

      # Two subtrees: paternal grandparents and maternal grandparents
      assert length(result.children) == 2
      [pat, mat] = result.children

      assert %Couple{} = pat
      assert pat.anchor_a.person.id == 4
      assert pat.anchor_b.person.id == 5
      assert pat.children == []

      assert %Couple{} = mat
      assert mat.anchor_a.person.id == 6
      assert mat.anchor_b.person.id == 7
      assert mat.children == []
    end

    test "asymmetric depth — only Father has parents" do
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_pat = make_person(4, "Grandpa-pat")
      gm_pat = make_person(5, "Grandma-pat")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_pat, 2)
        |> add_entry_helper(gm_pat, 2)
        |> add_couple_edge_helper(2, 3, :current_partner)
        |> add_couple_edge_helper(4, 5, :current_partner)
        |> add_parent_child_edge_helper(4, 2)
        |> add_parent_child_edge_helper(5, 2)
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      assert %Couple{} = result
      assert result.anchor_a.person.id == 2
      assert result.anchor_b.person.id == 3

      # Only one subtree: paternal side
      assert length(result.children) == 1
      [pat] = result.children

      assert %Couple{} = pat
      assert pat.anchor_a.person.id == 4
      assert pat.anchor_b.person.id == 5
      assert pat.children == []
    end

    test "lateral sibling on the LEFT side parent goes to the left of direct-line child" do
      # Father has sibling Uncle at gen 1. Father's parents = (GP-pat, GM-pat) at gen 2.
      # Focus's parents = Father + Mother.
      # Mother has no parents visible.
      # Expected: GP-pat+GM-pat couple has children = [Uncle_unit, Father's-upward-subtree]
      # Uncle is LEFT of the direct-line because he's a lateral of the LEFT parent (Father).
      # BUT in the ancestor tree, Father IS the direct-line, so:
      # The parent-couple (GP+GM) has children = [Uncle_unit, <direct-line child, which is empty since Father doesn't recurse further>]
      # Actually: Father doesn't have a separate subtree; the recursion builds GP+GM as Father's ancestor unit.
      # So the children of GP+GM couple = [Uncle_unit] to the left of the direct-line slot (empty since Father has no further ancestors).
      # Correction: since Father IS the entry that anchors the GP+GM couple, Father has NO separate child-unit entry in the children list.
      # The children list contains only laterals (siblings of Father = children of GP+GM other than Father).
      # Uncle is a lateral of Father, so he goes to the LEFT (before the direct-line child slot).
      # In the ancestor tree, the "children" of a parent-couple are: laterals + (optionally) deeper subtrees.
      # But the parent-couple represents the parent's own parents. So Father's parent-couple = GP+GM, and
      # the children of that %Couple{} are the OTHER children of GP+GM that are NOT Father (i.e., Uncle).
      # Uncle is a lateral of the LEFT parent (Father), so Uncle appears to the LEFT.
      # The result at the top level is Father+Mother couple, where Father's subtree = GP+GM couple (with Uncle lateral).
      # Mother has no parents => only Father's subtree in the children list.

      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_pat = make_person(4, "Grandpa-pat")
      gm_pat = make_person(5, "Grandma-pat")
      uncle = make_person(8, "Uncle")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_pat, 2)
        |> add_entry_helper(gm_pat, 2)
        |> add_entry_helper(uncle, 1)
        |> add_couple_edge_helper(2, 3, :current_partner)
        |> add_couple_edge_helper(4, 5, :current_partner)
        |> add_parent_child_edge_helper(4, 2)
        |> add_parent_child_edge_helper(5, 2)
        |> add_parent_child_edge_helper(4, 8)
        |> add_parent_child_edge_helper(5, 8)
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      # Top-level: Father + Mother couple
      assert %Couple{} = result
      assert result.anchor_a.person.id == 2
      assert result.anchor_b.person.id == 3

      # Father's subtree is a Couple (GP-pat + GM-pat) with Uncle as a left lateral
      assert length(result.children) == 1
      [father_subtree] = result.children

      assert %Couple{} = father_subtree
      assert father_subtree.anchor_a.person.id == 4
      assert father_subtree.anchor_b.person.id == 5

      # Uncle is a lateral of Father (left parent), so he appears BEFORE the direct-line slot
      # The children list of GP+GM couple: [Uncle_unit] (Father has no further upward subtree visible)
      assert length(father_subtree.children) == 1
      [uncle_unit] = father_subtree.children
      assert %Single{} = uncle_unit
      assert uncle_unit.anchor.person.id == 8
    end

    test "lateral sibling on the RIGHT side parent goes to the right" do
      # Mother has sibling Aunt at gen 1. Mother's parents = (GP-mat, GM-mat) at gen 2.
      # Focus's parents = Father + Mother.
      # Father has no parents visible.
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_mat = make_person(6, "Grandpa-mat")
      gm_mat = make_person(7, "Grandma-mat")
      aunt = make_person(9, "Aunt")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_mat, 2)
        |> add_entry_helper(gm_mat, 2)
        |> add_entry_helper(aunt, 1)
        |> add_couple_edge_helper(2, 3, :current_partner)
        |> add_couple_edge_helper(6, 7, :current_partner)
        |> add_parent_child_edge_helper(6, 3)
        |> add_parent_child_edge_helper(7, 3)
        |> add_parent_child_edge_helper(6, 9)
        |> add_parent_child_edge_helper(7, 9)
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      # Top-level: Father + Mother couple
      assert %Couple{} = result
      assert result.anchor_a.person.id == 2
      assert result.anchor_b.person.id == 3

      # Father has no parents => no Father subtree.
      # Mother's subtree is a Couple (GP-mat + GM-mat) with Aunt as a right lateral.
      assert length(result.children) == 1
      [mother_subtree] = result.children

      assert %Couple{} = mother_subtree
      assert mother_subtree.anchor_a.person.id == 6
      assert mother_subtree.anchor_b.person.id == 7

      # Aunt is a lateral of Mother (right parent), so she appears AFTER the direct-line slot
      assert length(mother_subtree.children) == 1
      [aunt_unit] = mother_subtree.children
      assert %Single{} = aunt_unit
      assert aunt_unit.anchor.person.id == 9
    end

    test "both sides have laterals — left lateral left of direct-line, right lateral right" do
      # Father has Uncle (lateral), Mother has Aunt (lateral).
      # Both Father and Mother have parents (grandparents).
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_pat = make_person(4, "Grandpa-pat")
      gm_pat = make_person(5, "Grandma-pat")
      gp_mat = make_person(6, "Grandpa-mat")
      gm_mat = make_person(7, "Grandma-mat")
      uncle = make_person(8, "Uncle")
      aunt = make_person(9, "Aunt")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_pat, 2)
        |> add_entry_helper(gm_pat, 2)
        |> add_entry_helper(gp_mat, 2)
        |> add_entry_helper(gm_mat, 2)
        |> add_entry_helper(uncle, 1)
        |> add_entry_helper(aunt, 1)
        |> add_couple_edge_helper(2, 3, :current_partner)
        |> add_couple_edge_helper(4, 5, :current_partner)
        |> add_couple_edge_helper(6, 7, :current_partner)
        |> add_parent_child_edge_helper(4, 2)
        |> add_parent_child_edge_helper(5, 2)
        |> add_parent_child_edge_helper(4, 8)
        |> add_parent_child_edge_helper(5, 8)
        |> add_parent_child_edge_helper(6, 3)
        |> add_parent_child_edge_helper(7, 3)
        |> add_parent_child_edge_helper(6, 9)
        |> add_parent_child_edge_helper(7, 9)
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      assert %Couple{} = result
      assert result.anchor_a.person.id == 2
      assert result.anchor_b.person.id == 3
      assert length(result.children) == 2

      [pat_subtree, mat_subtree] = result.children

      # Father's subtree (left): GP-pat + GM-pat, with Uncle lateral to the LEFT
      assert %Couple{} = pat_subtree
      assert pat_subtree.anchor_a.person.id == 4
      assert pat_subtree.anchor_b.person.id == 5
      assert length(pat_subtree.children) == 1
      [uncle_unit] = pat_subtree.children
      assert uncle_unit.anchor.person.id == 8

      # Mother's subtree (right): GP-mat + GM-mat, with Aunt lateral to the RIGHT
      assert %Couple{} = mat_subtree
      assert mat_subtree.anchor_a.person.id == 6
      assert mat_subtree.anchor_b.person.id == 7
      assert length(mat_subtree.children) == 1
      [aunt_unit] = mat_subtree.children
      assert aunt_unit.anchor.person.id == 9
    end

    test "duplicated parent is a leaf — no upward subtree" do
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_pat = make_person(4, "Grandpa-pat")
      gm_pat = make_person(5, "Grandma-pat")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        # Father is duplicated at gen 1
        |> add_entry_helper(father, 1, duplicated: true)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_pat, 2)
        |> add_entry_helper(gm_pat, 2)
        |> add_couple_edge_helper(2, 3, :current_partner)
        # Father's parents (would be reachable but Father is duplicated → should not recurse)
        |> add_couple_edge_helper(4, 5, :current_partner)
        |> add_parent_child_edge_helper(4, 2)
        |> add_parent_child_edge_helper(5, 2)
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)

      result = Layout.__build_ancestor_tree__(state, 1)

      assert %Couple{} = result
      # anchor_a is Father (duplicated), anchor_b is Mother
      assert result.anchor_a.person.id == 2
      assert result.anchor_a.duplicated == true
      assert result.anchor_b.person.id == 3
      # No children — Father is duplicated (leaf), Mother has no parents
      assert result.children == []
    end

    test "three-generation deep ancestry recurses correctly" do
      focus = make_person(1, "Focus")
      father = make_person(2, "Father")
      mother = make_person(3, "Mother")
      gp_pat = make_person(4, "GP-pat")
      gm_pat = make_person(5, "GM-pat")
      ggp_pat = make_person(10, "GGP-pat")
      ggm_pat = make_person(11, "GGM-pat")

      state =
        empty_state(1)
        |> add_entry_helper(focus, 0, focus: true)
        |> add_entry_helper(father, 1)
        |> add_entry_helper(mother, 1)
        |> add_entry_helper(gp_pat, 2)
        |> add_entry_helper(gm_pat, 2)
        |> add_entry_helper(ggp_pat, 3)
        |> add_entry_helper(ggm_pat, 3)
        |> add_couple_edge_helper(2, 3, :current_partner)
        |> add_couple_edge_helper(4, 5, :current_partner)
        |> add_couple_edge_helper(10, 11, :current_partner)
        |> add_parent_child_edge_helper(2, 1)
        |> add_parent_child_edge_helper(3, 1)
        |> add_parent_child_edge_helper(4, 2)
        |> add_parent_child_edge_helper(5, 2)
        |> add_parent_child_edge_helper(10, 4)
        |> add_parent_child_edge_helper(11, 4)

      result = Layout.__build_ancestor_tree__(state, 1)

      assert %Couple{} = result
      assert result.anchor_a.person.id == 2
      assert result.anchor_b.person.id == 3
      assert length(result.children) == 1

      [father_subtree] = result.children
      assert %Couple{} = father_subtree
      assert father_subtree.anchor_a.person.id == 4
      assert father_subtree.anchor_b.person.id == 5
      assert length(father_subtree.children) == 1

      [ggp_subtree] = father_subtree.children
      assert %Couple{} = ggp_subtree
      assert ggp_subtree.anchor_a.person.id == 10
      assert ggp_subtree.anchor_b.person.id == 11
      assert ggp_subtree.children == []
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
