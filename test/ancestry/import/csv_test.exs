defmodule Ancestry.Import.CSVTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Import.CSV
  alias Ancestry.Import.CSV.FamilyEcho
  alias Ancestry.People.Person

  @headers [
    "ID",
    "Full name",
    "Given names",
    "Nickname",
    "Title",
    "Suffix",
    "Color label",
    "Surname now",
    "Surname at birth",
    "Gender",
    "Deceased",
    "Mother ID",
    "Mother name",
    "Father ID",
    "Father name",
    "Parents type",
    "Second mother ID",
    "Second mother name",
    "Second father ID",
    "Second father name",
    "Second parents type",
    "Third mother ID",
    "Third mother name",
    "Third father ID",
    "Third father name",
    "Third parents type",
    "Birth date type",
    "Birth year",
    "Birth month",
    "Birth day",
    "Birth range end",
    "Death date type",
    "Death year",
    "Death month",
    "Death day",
    "Death range end",
    "Partner ID",
    "Partner name",
    "Partner title",
    "Partnership type",
    "Partnership date type",
    "Partnership year",
    "Partnership month",
    "Partnership day",
    "Partnership range end",
    "Ex-partner IDs",
    "Extra partner IDs",
    "Email",
    "Website",
    "Blog",
    "Photo site",
    "Home tel",
    "Work tel",
    "Mobile",
    "Skype",
    "Address",
    "Other contact",
    "Birth place",
    "Death place",
    "Cause of death",
    "Burial place",
    "Burial date type",
    "Burial year",
    "Burial month",
    "Burial day",
    "Burial range end",
    "Profession",
    "Company",
    "Interests",
    "Activities",
    "Bio notes"
  ]

  describe "import/3" do
    test "happy path: creates people and relationships" do
      rows = [
        csv_row(%{
          "ID" => "DAD1",
          "Given names" => "John",
          "Surname now" => "Smith",
          "Gender" => "Male",
          "Birth date type" => "Known",
          "Birth year" => "1960",
          "Birth month" => "5",
          "Birth day" => "15",
          "Partner ID" => "MOM1",
          "Partner name" => "Jane Smith"
        }),
        csv_row(%{
          "ID" => "MOM1",
          "Given names" => "Jane",
          "Surname now" => "Smith",
          "Gender" => "Female",
          "Birth date type" => "Known",
          "Birth year" => "1962",
          "Birth month" => "8",
          "Birth day" => "22"
        }),
        csv_row(%{
          "ID" => "KID1",
          "Given names" => "Billy",
          "Surname now" => "Smith",
          "Gender" => "Male",
          "Mother ID" => "MOM1",
          "Mother name" => "Jane Smith",
          "Father ID" => "DAD1",
          "Father name" => "John Smith",
          "Birth date type" => "Known",
          "Birth year" => "1990",
          "Birth month" => "3",
          "Birth day" => "10"
        }),
        csv_row(%{
          "ID" => "KID2",
          "Given names" => "Sally",
          "Surname now" => "Smith",
          "Gender" => "Female",
          "Mother ID" => "MOM1",
          "Mother name" => "Jane Smith",
          "Father ID" => "DAD1",
          "Father name" => "John Smith",
          "Birth date type" => "Known",
          "Birth year" => "1992",
          "Birth month" => "7",
          "Birth day" => "4"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary} = CSV.import(FamilyEcho, "Smith Family", path)

      assert summary.people_created == 4
      assert summary.people_skipped == 0
      assert summary.people_errors == []
      # DAD1->MOM1 partner, KID1 has mother+father, KID2 has mother+father = 5
      assert summary.relationships_created == 5
      assert summary.relationships_skipped == 0
      assert summary.relationships_errors == []
      assert summary.family.name == "Smith Family"
    end

    test "skips rows with no name" do
      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Surname now" => "Smith",
          "Gender" => "Male"
        }),
        csv_row(%{"ID" => "P2"})
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary} = CSV.import(FamilyEcho, "Test Family", path)

      assert summary.people_created == 1
      assert summary.people_skipped == 1
    end

    test "skips relationships when referenced person not found" do
      rows = [
        csv_row(%{
          "ID" => "KID1",
          "Given names" => "Billy",
          "Surname now" => "Smith",
          "Gender" => "Male",
          "Mother ID" => "MISSING_MOM",
          "Father ID" => "MISSING_DAD"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary} = CSV.import(FamilyEcho, "Test Family", path)

      assert summary.people_created == 1
      assert summary.relationships_created == 0
      assert summary.relationships_skipped == 2
    end

    test "returns error for file not found" do
      assert {:error, message} = CSV.import(FamilyEcho, "Test", "/nonexistent/file.csv")
      assert message =~ "File not found"
    end

    test "deduplicates symmetric partner relationships" do
      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "Alice",
          "Surname now" => "A",
          "Gender" => "Female",
          "Partner ID" => "P2",
          "Partner name" => "Bob B"
        }),
        csv_row(%{
          "ID" => "P2",
          "Given names" => "Bob",
          "Surname now" => "B",
          "Gender" => "Male",
          "Partner ID" => "P1",
          "Partner name" => "Alice A"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary} = CSV.import(FamilyEcho, "Test Family", path)

      assert summary.people_created == 2
      # First partner creates successfully, second is a duplicate and gets skipped
      assert summary.relationships_created == 1
      assert summary.relationships_skipped == 1
    end

    test "creates people with correct attributes" do
      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Nickname" => "Johnny",
          "Title" => "Dr",
          "Suffix" => "Jr",
          "Surname now" => "Smith",
          "Surname at birth" => "Jones",
          "Gender" => "Male",
          "Deceased" => "Y",
          "Birth date type" => "Known",
          "Birth year" => "1985",
          "Birth month" => "11",
          "Birth day" => "9",
          "Death date type" => "Known",
          "Death year" => "2020",
          "Death month" => "3",
          "Death day" => "15"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary} = CSV.import(FamilyEcho, "Attr Test", path)
      assert summary.people_created == 1

      person = Repo.get_by!(Person, external_id: "family_echo_P1")
      assert person.given_name == "John"
      assert person.surname == "Smith"
      assert person.surname_at_birth == "Jones"
      assert person.nickname == "Johnny"
      assert person.title == "Dr"
      assert person.suffix == "Jr"
      assert person.gender == "male"
      assert person.living == "no"
      assert person.birth_year == 1985
      assert person.birth_month == 11
      assert person.birth_day == 9
      assert person.death_year == 2020
      assert person.death_month == 3
      assert person.death_day == 15
    end
  end

  defp build_csv(rows) do
    header_line = Enum.join(@headers, ",")
    [header_line | rows] |> Enum.join("\n")
  end

  defp csv_row(values) do
    @headers
    |> Enum.map(fn header -> Map.get(values, header, "") end)
    |> Enum.join(",")
  end

  defp write_tmp_csv(content) do
    path = Path.join(System.tmp_dir!(), "test_import_#{System.unique_integer([:positive])}.csv")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
