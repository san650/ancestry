defmodule Ancestry.Import.CSV.FamilyEchoTest do
  use ExUnit.Case, async: true

  alias Ancestry.Import.CSV.FamilyEcho

  describe "parse_person/1" do
    test "parses a full row with all fields" do
      row =
        base_row(%{
          "ID" => "ABC123",
          "Given names" => "John",
          "Surname now" => "Smith",
          "Surname at birth" => "Jones",
          "Nickname" => "Johnny",
          "Title" => "Dr",
          "Suffix" => "Jr",
          "Gender" => "Male",
          "Deceased" => "",
          "Birth year" => "1985",
          "Birth month" => "11",
          "Birth day" => "9",
          "Death year" => "2020",
          "Death month" => "3",
          "Death day" => "15"
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.external_id == "family_echo_ABC123"
      assert attrs.given_name == "John"
      assert attrs.surname == "Smith"
      assert attrs.surname_at_birth == "Jones"
      assert attrs.nickname == "Johnny"
      assert attrs.title == "Dr"
      assert attrs.suffix == "Jr"
      assert attrs.gender == "male"
      assert attrs.deceased == false
      assert attrs.birth_year == 1985
      assert attrs.birth_month == 11
      assert attrs.birth_day == 9
      assert attrs.death_year == 2020
      assert attrs.death_month == 3
      assert attrs.death_day == 15
    end

    test "parses a deceased person" do
      row =
        base_row(%{
          "ID" => "DEF456",
          "Given names" => "Mary",
          "Surname now" => "Doe",
          "Deceased" => "Y",
          "Gender" => "Female"
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.deceased == true
      assert attrs.gender == "female"
    end

    test "skips rows with no name" do
      row =
        base_row(%{
          "ID" => "GHI789",
          "Given names" => "",
          "Surname now" => ""
        })

      assert {:skip, "no name"} = FamilyEcho.parse_person(row)
    end

    test "skips rows with blank-only name fields" do
      row =
        base_row(%{
          "ID" => "GHI789",
          "Given names" => "  ",
          "Surname now" => "  "
        })

      assert {:skip, "no name"} = FamilyEcho.parse_person(row)
    end

    test "maps unknown gender to other" do
      row =
        base_row(%{
          "ID" => "JKL012",
          "Given names" => "Pat",
          "Surname now" => "Smith",
          "Gender" => "Non-binary"
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.gender == "other"
    end

    test "maps empty gender to nil" do
      row =
        base_row(%{
          "ID" => "MNO345",
          "Given names" => "Alex",
          "Surname now" => "Smith",
          "Gender" => ""
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.gender == nil
    end

    test "handles blank date fields as nil" do
      row =
        base_row(%{
          "ID" => "PQR678",
          "Given names" => "Sam",
          "Surname now" => "Smith",
          "Birth year" => "",
          "Birth month" => "",
          "Birth day" => ""
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.birth_year == nil
      assert attrs.birth_month == nil
      assert attrs.birth_day == nil
    end

    test "accepts a person with only given_name" do
      row =
        base_row(%{
          "ID" => "STU901",
          "Given names" => "Madonna",
          "Surname now" => ""
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.given_name == "Madonna"
      assert attrs.surname == nil
    end

    test "accepts a person with only surname" do
      row =
        base_row(%{
          "ID" => "VWX234",
          "Given names" => "",
          "Surname now" => "Unknown"
        })

      assert {:ok, attrs} = FamilyEcho.parse_person(row)
      assert attrs.given_name == nil
      assert attrs.surname == "Unknown"
    end
  end

  describe "parse_relationships/1" do
    test "parses mother and father" do
      row =
        base_row(%{
          "ID" => "CHILD1",
          "Given names" => "Kid",
          "Surname now" => "Smith",
          "Mother ID" => "MOM1",
          "Father ID" => "DAD1"
        })

      rels = FamilyEcho.parse_relationships(row)
      assert length(rels) == 2

      assert {:parent, "family_echo_MOM1", "family_echo_CHILD1", %{role: "mother"}} in rels
      assert {:parent, "family_echo_DAD1", "family_echo_CHILD1", %{role: "father"}} in rels
    end

    test "parses partner" do
      row =
        base_row(%{
          "ID" => "P1",
          "Given names" => "Alice",
          "Surname now" => "A",
          "Partner ID" => "P2"
        })

      rels = FamilyEcho.parse_relationships(row)
      assert length(rels) == 1
      assert {:relationship, "family_echo_P1", "family_echo_P2", %{}} in rels
    end

    test "parses multiple ex-partners" do
      row =
        base_row(%{
          "ID" => "P1",
          "Given names" => "Bob",
          "Surname now" => "B",
          "Ex-partner IDs" => "EX1,EX2,EX3"
        })

      rels = FamilyEcho.parse_relationships(row)
      assert length(rels) == 3
      assert {:separated, "family_echo_P1", "family_echo_EX1", %{}} in rels
      assert {:separated, "family_echo_P1", "family_echo_EX2", %{}} in rels
      assert {:separated, "family_echo_P1", "family_echo_EX3", %{}} in rels
    end

    test "skips blank IDs" do
      row =
        base_row(%{
          "ID" => "P1",
          "Given names" => "Charlie",
          "Surname now" => "C",
          "Mother ID" => "",
          "Father ID" => "",
          "Partner ID" => "",
          "Ex-partner IDs" => ""
        })

      assert FamilyEcho.parse_relationships(row) == []
    end

    test "handles mixed present and blank IDs" do
      row =
        base_row(%{
          "ID" => "P1",
          "Given names" => "Diana",
          "Surname now" => "D",
          "Mother ID" => "MOM1",
          "Father ID" => "",
          "Partner ID" => "PARTNER1"
        })

      rels = FamilyEcho.parse_relationships(row)
      assert length(rels) == 2
      assert {:parent, "family_echo_MOM1", "family_echo_P1", %{role: "mother"}} in rels
      assert {:relationship, "family_echo_P1", "family_echo_PARTNER1", %{}} in rels
    end

    test "handles ex-partner IDs with extra whitespace" do
      row =
        base_row(%{
          "ID" => "P1",
          "Given names" => "Eve",
          "Surname now" => "E",
          "Ex-partner IDs" => "EX1, EX2 , EX3"
        })

      rels = FamilyEcho.parse_relationships(row)
      assert length(rels) == 3
      assert {:separated, "family_echo_P1", "family_echo_EX1", %{}} in rels
      assert {:separated, "family_echo_P1", "family_echo_EX2", %{}} in rels
      assert {:separated, "family_echo_P1", "family_echo_EX3", %{}} in rels
    end
  end

  # Helper to build a row map with sensible defaults for all FamilyEcho columns
  defp base_row(overrides) do
    defaults = %{
      "ID" => "TEST1",
      "Full name" => "",
      "Given names" => "",
      "Nickname" => "",
      "Title" => "",
      "Suffix" => "",
      "Color label" => "",
      "Surname now" => "",
      "Surname at birth" => "",
      "Gender" => "",
      "Deceased" => "",
      "Mother ID" => "",
      "Mother name" => "",
      "Father ID" => "",
      "Father name" => "",
      "Parents type" => "",
      "Second mother ID" => "",
      "Second mother name" => "",
      "Second father ID" => "",
      "Second father name" => "",
      "Second parents type" => "",
      "Third mother ID" => "",
      "Third mother name" => "",
      "Third father ID" => "",
      "Third father name" => "",
      "Third parents type" => "",
      "Birth date type" => "",
      "Birth year" => "",
      "Birth month" => "",
      "Birth day" => "",
      "Birth range end" => "",
      "Death date type" => "",
      "Death year" => "",
      "Death month" => "",
      "Death day" => "",
      "Death range end" => "",
      "Partner ID" => "",
      "Partner name" => "",
      "Partner title" => "",
      "Partnership type" => "",
      "Partnership date type" => "",
      "Partnership year" => "",
      "Partnership month" => "",
      "Partnership day" => "",
      "Partnership range end" => "",
      "Ex-partner IDs" => "",
      "Extra partner IDs" => "",
      "Email" => "",
      "Website" => "",
      "Blog" => "",
      "Photo site" => "",
      "Home tel" => "",
      "Work tel" => "",
      "Mobile" => "",
      "Skype" => "",
      "Address" => "",
      "Other contact" => "",
      "Birth place" => "",
      "Death place" => "",
      "Cause of death" => "",
      "Burial place" => "",
      "Burial date type" => "",
      "Burial year" => "",
      "Burial month" => "",
      "Burial day" => "",
      "Burial range end" => "",
      "Profession" => "",
      "Company" => "",
      "Interests" => "",
      "Activities" => "",
      "Bio notes" => ""
    }

    Map.merge(defaults, overrides)
  end
end
