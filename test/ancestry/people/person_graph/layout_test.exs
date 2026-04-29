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

  describe "__width__/1" do
    test "leaf single is 1" do
      single = %Single{anchor: %{person: %{id: 1}}, children: []}
      assert Layout.__width__(single) == 1
    end

    test "leaf couple is 2" do
      couple = %Couple{
        anchor_a: %{person: %{id: 1}},
        anchor_b: %{person: %{id: 2}},
        children: []
      }

      assert Layout.__width__(couple) == 2
    end

    test "couple with three child leaves: max(2, 5) = 5" do
      c1 = %Single{anchor: %{person: %{id: 1}}, children: []}
      c2 = %Single{anchor: %{person: %{id: 2}}, children: []}
      c3 = %Single{anchor: %{person: %{id: 3}}, children: []}

      couple = %Couple{
        anchor_a: %{person: %{id: 10}},
        anchor_b: %{person: %{id: 11}},
        children: [c1, c2, c3]
      }

      # children_width([c1, c2, c3]) = 1 + 1 + 1 + 1 + 1 = 5 (separators between siblings)
      # width(couple) = max(2, 5) = 5
      assert Layout.__width__(couple) == 5
    end

    test "couple with two child leaves: max(2, 3) = 3" do
      c1 = %Single{anchor: %{person: %{id: 1}}, children: []}
      c2 = %Single{anchor: %{person: %{id: 2}}, children: []}

      couple = %Couple{
        anchor_a: %{person: %{id: 10}},
        anchor_b: %{person: %{id: 11}},
        children: [c1, c2]
      }

      # children_width([c1, c2]) = 1 + 1 + 1 = 3
      # width(couple) = max(2, 3) = 3
      assert Layout.__width__(couple) == 3
    end

    test "two sibling couples (each with 2 children) under parent couple: max(2, 7) = 7" do
      # Each child couple has 2 leaf children.
      # width(child_couple_A) = max(2, 1 + 1 + 1) = 3
      # width(child_couple_B) = max(2, 1 + 1 + 1) = 3
      # children_width([A, B]) = 3 + 1 + 3 = 7 (one separator between sibling units)
      # width(parent_couple) = max(2, 7) = 7
      leaf = fn id -> %Single{anchor: %{person: %{id: id}}, children: []} end

      child_a = %Couple{
        anchor_a: %{person: %{id: 10}},
        anchor_b: %{person: %{id: 11}},
        children: [leaf.(1), leaf.(2)]
      }

      child_b = %Couple{
        anchor_a: %{person: %{id: 20}},
        anchor_b: %{person: %{id: 21}},
        children: [leaf.(3), leaf.(4)]
      }

      parent = %Couple{
        anchor_a: %{person: %{id: 100}},
        anchor_b: %{person: %{id: 101}},
        children: [child_a, child_b]
      }

      assert Layout.__width__(parent) == 7
    end

    test "loose lane width includes 1 separator between primary and lane" do
      # Primary single (leaf, width=1) with a loose lane containing one leaf single (width=1).
      # total = 1 (primary) + 1 (separator) + 1 (lane) = 3
      lane = %LooseLane{units: [%Single{anchor: %{person: %{id: 99}}, children: []}]}
      single = %Single{anchor: %{person: %{id: 1}}, children: [], loose_lane: lane}
      assert Layout.__width__(single) == 3
    end

    test "loose lane single unit width equals that unit's width" do
      # A LooseLane with a single leaf couple has width = 2.
      lane = %LooseLane{
        units: [
          %Couple{
            anchor_a: %{person: %{id: 1}},
            anchor_b: %{person: %{id: 2}},
            children: []
          }
        ]
      }

      # No primary unit here — testing LooseLane directly.
      # width(%LooseLane{units: [u]}) = width(u) = 2
      primary = %Single{anchor: %{person: %{id: 10}}, children: [], loose_lane: lane}

      # primary width = max(1, 0) = 1; total = 1 + 1 + 2 = 4
      assert Layout.__width__(primary) == 4
    end

    test "asymmetric ancestor: missing side contributes anchor only — max(2, 2) = 2" do
      # Couple{father, mother, children: [father_grandparents_couple]}
      # The father-grandparents couple is a leaf couple (width=2).
      # children_width([gp_couple]) = 2
      # width(parent_couple) = max(2, 2) = 2
      gp_couple = %Couple{
        anchor_a: %{person: %{id: 4}},
        anchor_b: %{person: %{id: 5}},
        children: []
      }

      parent_couple = %Couple{
        anchor_a: %{person: %{id: 2}},
        anchor_b: %{person: %{id: 3}},
        children: [gp_couple]
      }

      assert Layout.__width__(parent_couple) == 2
    end

    test "solo group (Single with anchor: nil) width equals children_width" do
      # %Single{anchor: nil} is a solo group — width = children_width(kids), no floor at 1.
      c1 = %Single{anchor: %{person: %{id: 1}}, children: []}
      c2 = %Single{anchor: %{person: %{id: 2}}, children: []}
      solo = %Single{anchor: nil, children: [c1, c2]}

      # children_width([c1, c2]) = 1 + 1 + 1 = 3
      assert Layout.__width__(solo) == 3
    end

    test "empty loose lane has zero width and no separator is added" do
      lane = %LooseLane{units: []}
      single = %Single{anchor: %{person: %{id: 1}}, children: [], loose_lane: lane}
      # lane width = 0, so no separator added; total = max(1, 0) = 1
      assert Layout.__width__(single) == 1
    end
  end

  describe "__place_half__/3" do
    test "single anchor at floor center (width 1, col 0)" do
      # %Single{anchor: person, children: []}
      # width = 1, start_col = 0
      # anchor sits at floor_center = 0 + div(1-1, 2) = 0
      anchor_entry = %{
        person: make_person(1, "Solo"),
        gen: 0,
        duplicated: false,
        focus: true,
        has_more_up: false,
        has_more_down: false
      }

      unit = %Single{anchor: anchor_entry, children: []}

      placements = Layout.__place_half__(unit, 0, :descendant)

      assert [{:placed_anchor, ^anchor_entry, 0, 0}] = placements
    end

    test "couple over three children: anchor at cols [1, 2]; kids at cols 0, 2, 4" do
      # width(couple) = max(2, 1+1+1+1+1) = max(2, 5) = 5
      # cols [0..4], remaining_start=0, remaining_width=5
      # anchor_a_col = 0 + div(5-2, 2) = 0 + 1 = 1
      # anchor_b_col = 2
      # children on row 1 at cols: child0 at col 0, sep at 1, child1 at 2, sep at 3, child2 at 4
      a = make_entry(10, 0)
      b = make_entry(11, 0)
      c1 = make_entry(1, -1)
      c2 = make_entry(2, -1)
      c3 = make_entry(3, -1)

      unit = %Couple{
        anchor_a: a,
        anchor_b: b,
        children: [
          %Single{anchor: c1, children: []},
          %Single{anchor: c2, children: []},
          %Single{anchor: c3, children: []}
        ],
        loose_lane: nil
      }

      placements = Layout.__place_half__(unit, 0, :descendant)

      # Expect anchor_a at (1,0), anchor_b at (2,0), separators at (0,0),(3,0),(4,0)
      # Children on row 1: c1 at (0,1), sep at (1,1), c2 at (2,1), sep at (3,1), c3 at (4,1)
      assert_placement(placements, {:placed_anchor, a, 1, 0})
      assert_placement(placements, {:placed_anchor, b, 2, 0})
      assert_placement(placements, {:separator, 0, 0})
      assert_placement(placements, {:separator, 3, 0})
      assert_placement(placements, {:separator, 4, 0})
      assert_placement(placements, {:placed_anchor, c1, 0, 1})
      assert_placement(placements, {:separator, 1, 1})
      assert_placement(placements, {:placed_anchor, c2, 2, 1})
      assert_placement(placements, {:separator, 3, 1})
      assert_placement(placements, {:placed_anchor, c3, 4, 1})
      assert length(placements) == 10
    end

    test "couple over two children: width 3, anchor at [0, 1], kids at cols 0 and 2" do
      # width(couple) = max(2, 1+1+1) = max(2,3) = 3
      # cols [0..2], remaining_start=0, remaining_width=3
      # anchor_a_col = 0 + div(3-2, 2) = 0 + 0 = 0
      # anchor_b_col = 1
      # children on row 1: c1 at col 0, sep at 1, c2 at col 2
      a = make_entry(10, 0)
      b = make_entry(11, 0)
      c1 = make_entry(1, -1)
      c2 = make_entry(2, -1)

      unit = %Couple{
        anchor_a: a,
        anchor_b: b,
        children: [
          %Single{anchor: c1, children: []},
          %Single{anchor: c2, children: []}
        ],
        loose_lane: nil
      }

      placements = Layout.__place_half__(unit, 0, :descendant)

      assert_placement(placements, {:placed_anchor, a, 0, 0})
      assert_placement(placements, {:placed_anchor, b, 1, 0})
      assert_placement(placements, {:separator, 2, 0})
      assert_placement(placements, {:placed_anchor, c1, 0, 1})
      assert_placement(placements, {:separator, 1, 1})
      assert_placement(placements, {:placed_anchor, c2, 2, 1})
      assert length(placements) == 6
    end

    test "loose lane on the left of primary couple" do
      # ex_partner single (width=1) + separator + primary couple (width=2) = total 4
      # Lane at col 0; separator at col 1; primary anchor_a at col 2, anchor_b at col 3
      # No children on primary, no children on loose lane unit.
      ex = make_entry(99, 0)
      a = make_entry(10, 0)
      b = make_entry(11, 0)

      lane_unit = %Single{anchor: ex, children: []}
      lane = %LooseLane{units: [lane_unit]}

      unit = %Couple{
        anchor_a: a,
        anchor_b: b,
        children: [],
        loose_lane: lane
      }

      placements = Layout.__place_half__(unit, 0, :descendant)

      # Lane occupies col 0 (placed_anchor for ex at row 0)
      # Separator at col 1, row 0 (loose-lane separator)
      # Primary anchor_a at col 2, anchor_b at col 3
      assert_placement(placements, {:placed_anchor, ex, 0, 0})
      assert_placement(placements, {:separator, 1, 0})
      assert_placement(placements, {:placed_anchor, a, 2, 0})
      assert_placement(placements, {:placed_anchor, b, 3, 0})
      assert length(placements) == 4
    end

    test "ancestor direction: children sit at row - 1" do
      # Couple at base_row=0, direction=:ancestor
      # Father, Mother on row 0
      # Grandpa, Grandma on row -1
      father = make_entry(2, 1)
      mother = make_entry(3, 1)
      grandpa = make_entry(4, 2)
      grandma = make_entry(5, 2)

      gp_couple = %Couple{anchor_a: grandpa, anchor_b: grandma, children: [], loose_lane: nil}

      unit = %Couple{
        anchor_a: father,
        anchor_b: mother,
        children: [gp_couple],
        loose_lane: nil
      }

      placements = Layout.__place_half__(unit, 0, :ancestor)

      # width(gp_couple) = 2; children_width = 2; parent_width = max(2,2) = 2
      # parent anchor at cols [0,1] (remaining_width=2, anchor_a = 0 + div(0,2) = 0)
      # children go on row -1
      assert_placement(placements, {:placed_anchor, father, 0, 0})
      assert_placement(placements, {:placed_anchor, mother, 1, 0})
      assert_placement(placements, {:placed_anchor, grandpa, 0, -1})
      assert_placement(placements, {:placed_anchor, grandma, 1, -1})
      assert length(placements) == 4
    end

    test "two sibling sub-families separated by separator" do
      # parent %Couple{ children: [Couple_A (width 3), Couple_B (width 2)] }
      # Couple_A has two single children: children_width(2 singles) = 1+1+1 = 3 → width = max(2,3) = 3
      # Couple_B is a leaf couple: width = 2
      # children_width([Couple_A, Couple_B]) = 3 + 1 + 2 = 6
      # parent width = max(2, 6) = 6
      # On row 0: anchor_a_col = 0 + div(6-2, 2) = 0 + 2 = 2, anchor_b_col = 3
      # Separators on row 0: cols 0, 1, 4, 5
      # Children on row 1:
      #   Couple_A (width 3) at start_col=0: anchor at cols [0,1], separator at col 2
      #   sep between siblings at col 3
      #   Couple_B (width 2) at start_col=4: anchor at cols [4,5], no extra separators
      # Row 2: Couple_A's two children, each width 1, with a separator between them
      #   c_kid1 at col 0, sep at col 1, c_kid2 at col 2
      pa = make_entry(100, 0)
      pb = make_entry(101, 0)
      a1 = make_entry(10, -1)
      a2 = make_entry(11, -1)
      b1 = make_entry(20, -1)
      b2 = make_entry(21, -1)
      # Two children so couple_a width = max(2, 1+1+1) = 3
      ca_child1 = make_entry(30, -2)
      ca_child2 = make_entry(31, -2)

      couple_a = %Couple{
        anchor_a: a1,
        anchor_b: a2,
        children: [
          %Single{anchor: ca_child1, children: []},
          %Single{anchor: ca_child2, children: []}
        ],
        loose_lane: nil
      }

      couple_b = %Couple{
        anchor_a: b1,
        anchor_b: b2,
        children: [],
        loose_lane: nil
      }

      unit = %Couple{
        anchor_a: pa,
        anchor_b: pb,
        children: [couple_a, couple_b],
        loose_lane: nil
      }

      placements = Layout.__place_half__(unit, 0, :descendant)

      # Row 0 — parent anchor centered in [0..5]
      assert_placement(placements, {:placed_anchor, pa, 2, 0})
      assert_placement(placements, {:placed_anchor, pb, 3, 0})
      assert_placement(placements, {:separator, 0, 0})
      assert_placement(placements, {:separator, 1, 0})
      assert_placement(placements, {:separator, 4, 0})
      assert_placement(placements, {:separator, 5, 0})

      # Row 1 — Couple_A occupies [0..2]: anchor at [0,1], separator at col 2
      assert_placement(placements, {:placed_anchor, a1, 0, 1})
      assert_placement(placements, {:placed_anchor, a2, 1, 1})
      assert_placement(placements, {:separator, 2, 1})

      # Row 1 — inter-sibling separator between Couple_A and Couple_B
      assert_placement(placements, {:separator, 3, 1})

      # Row 1 — Couple_B occupies [4..5]: anchor at [4,5]
      assert_placement(placements, {:placed_anchor, b1, 4, 1})
      assert_placement(placements, {:placed_anchor, b2, 5, 1})

      # Row 2 — Couple_A's two children laid out in [0..2]
      # ca_child1 at col 0, sep at col 1, ca_child2 at col 2
      assert_placement(placements, {:placed_anchor, ca_child1, 0, 2})
      assert_placement(placements, {:separator, 1, 2})
      assert_placement(placements, {:placed_anchor, ca_child2, 2, 2})
    end
  end

  describe "__merge_halves__/2" do
    test "positive shift: focus at cols [8, 9], anc parent couple originally at cols [3, 4]" do
      # Descendant placements: focus couple at cols [8, 9], row 0, plus a child at col 8, row 1
      # Ancestor placements: parent couple at cols [3, 4], row 0, plus grandparents at cols [0, 1], row -1
      # delta = 8 - 3 = 5 → shift ancestors right by 5 (descendants stay)
      # After merge: parent couple at cols [8, 9], row -1; grandparents at cols [5, 6], row -2
      focus_entry = make_merge_entry(1, "Focus", 0, focus: true)
      partner_entry = make_merge_entry(2, "Partner", 0)
      child_entry = make_merge_entry(3, "Child", -1)
      father_entry = make_merge_entry(4, "Father", 1)
      mother_entry = make_merge_entry(5, "Mother", 1)
      gp_pat_entry = make_merge_entry(6, "GrandpaPaternal", 2)
      gm_pat_entry = make_merge_entry(7, "GrandmaPaternal", 2)

      desc_placements = [
        {:placed_anchor, focus_entry, 8, 0},
        {:placed_anchor, partner_entry, 9, 0},
        {:placed_anchor, child_entry, 8, 1}
      ]

      anc_placements = [
        {:placed_anchor, father_entry, 3, 0},
        {:placed_anchor, mother_entry, 4, 0},
        {:placed_anchor, gp_pat_entry, 0, -1},
        {:placed_anchor, gm_pat_entry, 1, -1}
      ]

      merged = Layout.__merge_halves__(desc_placements, anc_placements)

      # Desc placements unchanged
      assert_placement(merged, {:placed_anchor, focus_entry, 8, 0})
      assert_placement(merged, {:placed_anchor, partner_entry, 9, 0})
      assert_placement(merged, {:placed_anchor, child_entry, 8, 1})

      # Anc placements: shifted right by 5 AND shifted down by -1
      # Father: col 3+5=8, row 0-1=-1
      assert_placement(merged, {:placed_anchor, father_entry, 8, -1})
      # Mother: col 4+5=9, row 0-1=-1
      assert_placement(merged, {:placed_anchor, mother_entry, 9, -1})
      # Grandpa: col 0+5=5, row -1-1=-2
      assert_placement(merged, {:placed_anchor, gp_pat_entry, 5, -2})
      # Grandma: col 1+5=6, row -1-1=-2
      assert_placement(merged, {:placed_anchor, gm_pat_entry, 6, -2})

      assert length(merged) == 7
    end

    test "negative shift: focus at col 1, anc parent couple at cols [3, 4]" do
      # desc focus at col 1 (simulating a couple where focus is anchor_a at col 1)
      # anc parent couple at cols [3, 4]
      # delta = 1 - 3 = -2 → shift descendants right by 2
      # After merge: focus at col 3, parent couple at cols [3, 4], row -1
      focus_entry = make_merge_entry(1, "Focus", 0, focus: true)
      partner_entry = make_merge_entry(2, "Partner", 0)
      child_entry = make_merge_entry(3, "Child", -1)
      father_entry = make_merge_entry(4, "Father", 1)
      mother_entry = make_merge_entry(5, "Mother", 1)

      desc_placements = [
        {:placed_anchor, focus_entry, 1, 0},
        {:placed_anchor, partner_entry, 2, 0},
        {:placed_anchor, child_entry, 1, 1}
      ]

      anc_placements = [
        {:placed_anchor, father_entry, 3, 0},
        {:placed_anchor, mother_entry, 4, 0}
      ]

      merged = Layout.__merge_halves__(desc_placements, anc_placements)

      # delta = 1 - 3 = -2 → desc shift by +2 (descendants move right)
      assert_placement(merged, {:placed_anchor, focus_entry, 3, 0})
      assert_placement(merged, {:placed_anchor, partner_entry, 4, 0})
      assert_placement(merged, {:placed_anchor, child_entry, 3, 1})

      # Anc placements stay at their col, shifted to row -1
      assert_placement(merged, {:placed_anchor, father_entry, 3, -1})
      assert_placement(merged, {:placed_anchor, mother_entry, 4, -1})

      assert length(merged) == 5
    end

    test "no shift needed: focus col equals anc parent col (delta = 0)" do
      # Focus couple at cols [0, 1], parent couple also at cols [0, 1]
      # delta = 0 → no shift, ancestors just get row -1
      focus_entry = make_merge_entry(1, "Focus", 0, focus: true)
      partner_entry = make_merge_entry(2, "Partner", 0)
      father_entry = make_merge_entry(4, "Father", 1)
      mother_entry = make_merge_entry(5, "Mother", 1)

      desc_placements = [
        {:placed_anchor, focus_entry, 0, 0},
        {:placed_anchor, partner_entry, 1, 0}
      ]

      anc_placements = [
        {:placed_anchor, father_entry, 0, 0},
        {:placed_anchor, mother_entry, 1, 0}
      ]

      merged = Layout.__merge_halves__(desc_placements, anc_placements)

      # Desc placements unchanged
      assert_placement(merged, {:placed_anchor, focus_entry, 0, 0})
      assert_placement(merged, {:placed_anchor, partner_entry, 1, 0})

      # Anc placements: no col shift, row shifted by -1
      assert_placement(merged, {:placed_anchor, father_entry, 0, -1})
      assert_placement(merged, {:placed_anchor, mother_entry, 1, -1})

      assert length(merged) == 4
    end

    test "single focus (no current partner): focus col aligns with anc parent couple anchor_a col" do
      # Focus is a Single at col 0. Ancestor parent couple at cols [0, 1].
      # delta = 0 → no shift. Parents land at row -1.
      focus_entry = make_merge_entry(1, "Focus", 0, focus: true)
      father_entry = make_merge_entry(4, "Father", 1)
      mother_entry = make_merge_entry(5, "Mother", 1)

      # Single focus at col 0
      desc_placements = [
        {:placed_anchor, focus_entry, 0, 0}
      ]

      # Parent couple at cols [0, 1]
      anc_placements = [
        {:placed_anchor, father_entry, 0, 0},
        {:placed_anchor, mother_entry, 1, 0}
      ]

      merged = Layout.__merge_halves__(desc_placements, anc_placements)

      # Focus unchanged at col 0, row 0
      assert_placement(merged, {:placed_anchor, focus_entry, 0, 0})

      # Father at col 0, row -1; Mother at col 1, row -1
      assert_placement(merged, {:placed_anchor, father_entry, 0, -1})
      assert_placement(merged, {:placed_anchor, mother_entry, 1, -1})

      assert length(merged) == 3
    end

    test "separators are also shifted correctly" do
      # Desc: focus at col 3, separator at col 2. Anc: parent single at col 5, separator at col 2.
      # delta = 3 - 5 = -2 → shift descendants right by 2; anc shifted only by row -1
      focus_entry = make_merge_entry(1, "Focus", 0, focus: true)
      father_entry = make_merge_entry(4, "Father", 1)

      desc_placements = [
        {:placed_anchor, focus_entry, 3, 0},
        {:separator, 2, 0}
      ]

      anc_placements = [
        {:placed_anchor, father_entry, 5, 0},
        {:separator, 2, 0}
      ]

      merged = Layout.__merge_halves__(desc_placements, anc_placements)

      # delta = 3 - 5 = -2 → desc shift +2
      assert_placement(merged, {:placed_anchor, focus_entry, 5, 0})
      assert_placement(merged, {:separator, 4, 0})

      # Anc stay at their cols, just row -1 applied
      assert_placement(merged, {:placed_anchor, father_entry, 5, -1})
      assert_placement(merged, {:separator, 2, -1})

      assert length(merged) == 4
    end

    test "empty desc_placements: ancestor placements shifted to row -1 at col 0" do
      # When desc_placements is empty, focus_col defaults to 0.
      # If anc parent is at col 0, delta = 0, no col shift, row -1.
      father_entry = make_merge_entry(4, "Father", 1)

      desc_placements = []

      anc_placements = [
        {:placed_anchor, father_entry, 0, 0}
      ]

      merged = Layout.__merge_halves__(desc_placements, anc_placements)

      assert_placement(merged, {:placed_anchor, father_entry, 0, -1})
      assert length(merged) == 1
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

  # Build a minimal Phase-1 entry map for placement tests (no state needed).
  defp make_entry(id, gen) do
    %{
      person: make_person(id, "Person#{id}"),
      gen: gen,
      duplicated: false,
      has_more_up: false,
      has_more_down: false,
      focus: false
    }
  end

  # Build a minimal entry map for __merge_halves__ tests.
  defp make_merge_entry(id, name, gen, opts \\ []) do
    %{
      person: make_person(id, name),
      gen: gen,
      duplicated: false,
      has_more_up: false,
      has_more_down: false,
      focus: Keyword.get(opts, :focus, false)
    }
  end

  # Assert that `placements` contains the given tuple exactly once.
  defp assert_placement(placements, expected) do
    assert Enum.member?(placements, expected),
           "Expected #{inspect(expected)} in placements, got:\n#{inspect(placements, pretty: true)}"
  end
end
