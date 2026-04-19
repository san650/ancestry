defmodule Ancestry.Kinship.LabelTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.Label

  # In English locale, Gettext.pgettext returns the msgid as-is (no .po translations for English).

  describe "direct line ascending" do
    test "parent (0,1)" do
      assert Label.format(0, 1, false, "other") == "Parent"
    end

    test "grandparent (0,2)" do
      assert Label.format(0, 2, false, "other") == "Grandparent"
    end

    test "great grandparent (0,3)" do
      assert Label.format(0, 3, false, "other") == "Great Grandparent"
    end

    test "great great grandparent (0,4)" do
      assert Label.format(0, 4, false, "other") == "Great Great Grandparent"
    end

    test "3rd great grandparent (0,5)" do
      assert Label.format(0, 5, false, "other") == "3rd Great Grandparent"
    end

    test "4th great grandparent (0,6)" do
      assert Label.format(0, 6, false, "other") == "4th Great Grandparent"
    end

    test "7th great grandparent (0,9)" do
      assert Label.format(0, 9, false, "other") == "7th Great Grandparent"
    end
  end

  describe "direct line descending" do
    test "child (1,0)" do
      assert Label.format(1, 0, false, "other") == "Child"
    end

    test "grandchild (2,0)" do
      assert Label.format(2, 0, false, "other") == "Grandchild"
    end

    test "great grandchild (3,0)" do
      assert Label.format(3, 0, false, "other") == "Great Grandchild"
    end

    test "great great grandchild (4,0)" do
      assert Label.format(4, 0, false, "other") == "Great Great Grandchild"
    end

    test "3rd great grandchild (5,0)" do
      assert Label.format(5, 0, false, "other") == "3rd Great Grandchild"
    end
  end

  describe "siblings" do
    test "sibling (1,1) half?=false" do
      assert Label.format(1, 1, false, "other") == "Sibling"
    end

    test "half-sibling (1,1) half?=true" do
      assert Label.format(1, 1, true, "other") == "Half-Sibling"
    end
  end

  describe "uncle & aunt chain" do
    test "uncle/aunt (1,2)" do
      assert Label.format(1, 2, false, "other") == "Uncle & Aunt"
    end

    test "great uncle/aunt (1,3)" do
      assert Label.format(1, 3, false, "other") == "Great Uncle & Aunt"
    end

    test "great grand uncle/aunt (1,4)" do
      assert Label.format(1, 4, false, "other") == "Great Grand Uncle & Aunt"
    end

    test "1st great grand uncle/aunt (1,5)" do
      assert Label.format(1, 5, false, "other") == "1st Great Grand Uncle & Aunt"
    end

    test "2nd great grand uncle/aunt (1,6)" do
      assert Label.format(1, 6, false, "other") == "2nd Great Grand Uncle & Aunt"
    end
  end

  describe "nephew & niece chain" do
    test "nephew/niece (2,1)" do
      assert Label.format(2, 1, false, "other") == "Nephew & Niece"
    end

    test "grand nephew/niece (3,1)" do
      assert Label.format(3, 1, false, "other") == "Grand Nephew & Niece"
    end

    test "great grand nephew/niece (4,1)" do
      assert Label.format(4, 1, false, "other") == "Great Grand Nephew & Niece"
    end

    test "1st great grand nephew/niece (5,1)" do
      assert Label.format(5, 1, false, "other") == "1st Great Grand Nephew & Niece"
    end

    test "2nd great grand nephew/niece (6,1)" do
      assert Label.format(6, 1, false, "other") == "2nd Great Grand Nephew & Niece"
    end
  end

  describe "same-generation cousins" do
    test "first cousin (2,2)" do
      assert Label.format(2, 2, false, "other") == "First Cousin"
    end

    test "second cousin (3,3)" do
      assert Label.format(3, 3, false, "other") == "Second Cousin"
    end

    test "third cousin (4,4)" do
      assert Label.format(4, 4, false, "other") == "Third Cousin"
    end

    test "half first cousin (2,2) half?=true" do
      assert Label.format(2, 2, true, "other") == "Half-First Cousin"
    end

    test "half second cousin (3,3) half?=true" do
      assert Label.format(3, 3, true, "other") == "Half-Second Cousin"
    end
  end

  describe "removed cousins (English locale)" do
    test "first cousin once removed ascending (2,3)" do
      assert Label.format(2, 3, false, "other") == "First Cousin, Once Removed"
    end

    test "first cousin once removed descending (3,2)" do
      assert Label.format(3, 2, false, "other") == "First Cousin, Once Removed"
    end

    test "second cousin once removed (3,4)" do
      assert Label.format(3, 4, false, "other") == "Second Cousin, Once Removed"
    end

    test "first cousin twice removed (2,4)" do
      assert Label.format(2, 4, false, "other") == "First Cousin, Twice Removed"
    end

    test "first cousin 3 times removed (2,5)" do
      assert Label.format(2, 5, false, "other") == "First Cousin, 3 Times Removed"
    end

    test "half first cousin once removed (2,3) half?=true" do
      assert Label.format(2, 3, true, "other") == "Half-First Cousin, Once Removed"
    end
  end

  describe "gender/nil handling" do
    test "nil gender is treated as 'other'" do
      assert Label.format(0, 1, false, nil) == "Parent"
    end

    test "unknown gender string is treated as 'other'" do
      assert Label.format(1, 1, false, "nonbinary") == "Sibling"
    end

    test "male gender passes through correctly" do
      assert Label.format(0, 1, false, "male") == "Parent"
    end

    test "female gender passes through correctly" do
      assert Label.format(0, 1, false, "female") == "Parent"
    end
  end
end
