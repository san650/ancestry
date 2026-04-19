defmodule Ancestry.Kinship.InLawLabelTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.InLawLabel

  describe "format/3 - spouse" do
    test "spouse label" do
      assert InLawLabel.format(:spouse, :spouse, "male") == "Spouse"
      assert InLawLabel.format(:spouse, :spouse, "female") == "Spouse"
      assert InLawLabel.format(:spouse, :spouse, nil) == "Spouse"
    end
  end

  describe "format/3 - core special terms" do
    test "parent-in-law" do
      assert InLawLabel.format(0, 1, "male") == "Parent-in-law"
      assert InLawLabel.format(0, 1, "female") == "Parent-in-law"
    end

    test "child-in-law" do
      assert InLawLabel.format(1, 0, "male") == "Child-in-law"
      assert InLawLabel.format(1, 0, "female") == "Child-in-law"
    end

    test "sibling-in-law" do
      assert InLawLabel.format(1, 1, "male") == "Sibling-in-law"
      assert InLawLabel.format(1, 1, "female") == "Sibling-in-law"
    end
  end

  describe "format/3 - extended in-law terms (English)" do
    test "grandparent-in-law" do
      assert InLawLabel.format(0, 2, "male") == "Grandparent-in-law"
    end

    test "grandchild-in-law" do
      assert InLawLabel.format(2, 0, "male") == "Grandchild-in-law"
    end

    test "uncle/aunt-in-law" do
      assert InLawLabel.format(1, 2, "male") == "Uncle/Aunt-in-law"
    end

    test "nephew/niece-in-law" do
      assert InLawLabel.format(2, 1, "male") == "Nephew/Niece-in-law"
    end

    test "cousin-in-law" do
      assert InLawLabel.format(2, 2, "male") == "Cousin-in-law"
    end

    test "great grandparent-in-law" do
      assert InLawLabel.format(0, 3, "male") == "Great Grandparent-in-law"
    end

    test "great uncle/aunt-in-law" do
      assert InLawLabel.format(1, 3, "male") == "Great Uncle/Aunt-in-law"
    end

    test "grand nephew/niece-in-law" do
      assert InLawLabel.format(3, 1, "male") == "Grand Nephew/Niece-in-law"
    end

    test "second cousin-in-law" do
      assert InLawLabel.format(3, 3, "male") =~ "Cousin-in-law"
    end

    test "removed cousin-in-law" do
      assert InLawLabel.format(2, 3, "male") =~ "Cousin"
      assert InLawLabel.format(2, 3, "male") =~ "-in-law"
    end
  end
end
