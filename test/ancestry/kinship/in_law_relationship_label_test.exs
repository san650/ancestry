defmodule Ancestry.Kinship.InLawRelationshipLabelTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Kinship.InLawRelationshipLabel, as: InLawLabel

  describe "format/3 - spouse" do
    test "spouse label — gendered" do
      assert InLawLabel.format(:spouse, :spouse, "male") == "Husband"
      assert InLawLabel.format(:spouse, :spouse, "female") == "Wife"
      assert InLawLabel.format(:spouse, :spouse, nil) == "Spouse"
    end
  end

  describe "format/3 - core special terms" do
    test "parent-in-law — gendered" do
      assert InLawLabel.format(0, 1, "male") == "Father-in-law"
      assert InLawLabel.format(0, 1, "female") == "Mother-in-law"
    end

    test "child-in-law — gendered" do
      assert InLawLabel.format(1, 0, "male") == "Son-in-law"
      assert InLawLabel.format(1, 0, "female") == "Daughter-in-law"
    end

    test "sibling-in-law — gendered" do
      assert InLawLabel.format(1, 1, "male") == "Brother-in-law"
      assert InLawLabel.format(1, 1, "female") == "Sister-in-law"
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

  describe "format/3 - Spanish locale" do
    setup do
      Gettext.put_locale(Web.Gettext, "es-UY")
      on_exit(fn -> Gettext.put_locale(Web.Gettext, "en") end)
    end

    test "spouse — male" do
      assert InLawLabel.format(:spouse, :spouse, "male") == "Esposo"
    end

    test "spouse — female" do
      assert InLawLabel.format(:spouse, :spouse, "female") == "Esposa"
    end

    test "parent-in-law — male (suegro)" do
      assert InLawLabel.format(0, 1, "male") == "Suegro"
    end

    test "parent-in-law — female (suegra)" do
      assert InLawLabel.format(0, 1, "female") == "Suegra"
    end

    test "child-in-law — male (yerno)" do
      assert InLawLabel.format(1, 0, "male") == "Yerno"
    end

    test "child-in-law — female (nuera)" do
      assert InLawLabel.format(1, 0, "female") == "Nuera"
    end

    test "sibling-in-law — male (cuñado)" do
      assert InLawLabel.format(1, 1, "male") == "Cuñado"
    end

    test "sibling-in-law — female (cuñada)" do
      assert InLawLabel.format(1, 1, "female") == "Cuñada"
    end

    test "grandparent-in-law — male (abuelo político)" do
      assert InLawLabel.format(0, 2, "male") == "Abuelo político"
    end

    test "grandparent-in-law — female (abuela política)" do
      assert InLawLabel.format(0, 2, "female") == "Abuela política"
    end

    test "uncle-in-law — male (tío político)" do
      assert InLawLabel.format(1, 2, "male") == "Tío político"
    end

    test "aunt-in-law — female (tía política)" do
      assert InLawLabel.format(1, 2, "female") == "Tía política"
    end

    test "nephew-in-law — male (sobrino político)" do
      assert InLawLabel.format(2, 1, "male") == "Sobrino político"
    end

    test "cousin-in-law — male (primo político)" do
      assert InLawLabel.format(2, 2, "male") == "Primo político"
    end

    test "cousin-in-law — female (prima política)" do
      assert InLawLabel.format(2, 2, "female") == "Prima política"
    end

    test "great uncle-in-law — male (tío abuelo político)" do
      assert InLawLabel.format(1, 3, "male") == "Tío abuelo político"
    end

    test "removed cousin in-law — tío segundo político" do
      assert InLawLabel.format(2, 3, "male") == "Tío segundo político"
    end
  end
end
