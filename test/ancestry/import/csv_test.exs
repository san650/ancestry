defmodule Ancestry.Import.CSVTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Import.CSV
  alias Ancestry.Import.CSV.FamilyEcho
  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships.Relationship

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

  setup do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    %{org: org}
  end

  describe "import/4" do
    test "happy path: creates people and relationships", %{org: org} do
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

      assert {:ok, summary} = CSV.import(FamilyEcho, "Smith Family", path, org)

      assert summary.people_created == 4
      assert summary.people_skipped == 0
      assert summary.people_errors == []
      # DAD1->MOM1 partner, KID1 has mother+father, KID2 has mother+father = 5
      assert summary.relationships_created == 5
      assert summary.relationships_duplicates == 0
      assert summary.relationships_errors == []
      assert summary.family.name == "Smith Family"
    end

    test "skips rows with no name", %{org: org} do
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

      assert {:ok, summary} = CSV.import(FamilyEcho, "Test Family", path, org)

      assert summary.people_created == 1
      assert summary.people_skipped == 1
    end

    test "skips relationships when referenced person not found", %{org: org} do
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

      assert {:ok, summary} = CSV.import(FamilyEcho, "Test Family", path, org)

      assert summary.people_created == 1
      assert summary.relationships_created == 0
      assert length(summary.relationships_errors) == 2
    end

    test "returns error for file not found", %{org: org} do
      assert {:error, message} = CSV.import(FamilyEcho, "Test", "/nonexistent/file.csv", org)
      assert message =~ "File not found"
    end

    test "deduplicates symmetric partner relationships", %{org: org} do
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

      assert {:ok, summary} = CSV.import(FamilyEcho, "Test Family", path, org)

      assert summary.people_created == 2
      # First partner creates successfully, second is a duplicate
      assert summary.relationships_created == 1
      assert summary.relationships_duplicates == 1
    end

    test "creates people with correct attributes", %{org: org} do
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

      assert {:ok, summary} = CSV.import(FamilyEcho, "Attr Test", path, org)
      assert summary.people_created == 1

      person = Repo.get_by!(Person, external_id: "family_echo_P1")
      assert person.given_name == "John"
      assert person.surname == "Smith"
      assert person.surname_at_birth == "Jones"
      assert person.nickname == "Johnny"
      assert person.title == "Dr"
      assert person.suffix == "Jr"
      assert person.gender == "male"
      assert person.deceased == true
      assert person.birth_year == 1985
      assert person.birth_month == 11
      assert person.birth_day == 9
      assert person.death_year == 2020
      assert person.death_month == 3
      assert person.death_day == 15
    end
  end

  describe "import_for_family/3" do
    test "imports people into an existing family" do
      org = insert(:organization)
      family = insert(:family, organization: org)

      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "Alice",
          "Surname now" => "Smith",
          "Gender" => "Female"
        }),
        csv_row(%{
          "ID" => "P2",
          "Given names" => "Bob",
          "Surname now" => "Smith",
          "Gender" => "Male"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary} = CSV.import_for_family(FamilyEcho, family, path)
      assert summary.family.id == family.id
      assert summary.people_created == 2
      assert summary.people_skipped == 0
    end

    test "returns error for missing file" do
      org = insert(:organization)
      family = insert(:family, organization: org)

      assert {:error, "File not found:" <> _} =
               CSV.import_for_family(FamilyEcho, family, "/nonexistent.csv")
    end
  end

  describe "re-import" do
    test "reuses existing family by name", %{org: org} do
      rows = [csv_row(%{"ID" => "P1", "Given names" => "John", "Surname now" => "Doe"})]
      path = write_tmp_csv(build_csv(rows))

      assert {:ok, first} = CSV.import(FamilyEcho, "Doe Family", path, org)
      assert {:ok, second} = CSV.import(FamilyEcho, "Doe Family", path, org)

      assert first.family.id == second.family.id
    end

    test "reports unchanged people on re-import", %{org: org} do
      rows = [csv_row(%{"ID" => "P1", "Given names" => "John", "Surname now" => "Doe"})]
      path = write_tmp_csv(build_csv(rows))

      assert {:ok, _first} = CSV.import(FamilyEcho, "Doe Family", path, org)
      assert {:ok, second} = CSV.import(FamilyEcho, "Doe Family", path, org)

      assert second.people_created == 0
      assert second.people_unchanged == 1
      assert "John Doe" in second.people_unchanged_names
    end

    test "updates changed people on re-import", %{org: org} do
      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Surname now" => "Doe",
          "Birth year" => "1990"
        })
      ]

      path = write_tmp_csv(build_csv(rows))
      assert {:ok, _first} = CSV.import(FamilyEcho, "Doe Family", path, org)

      updated_rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Surname now" => "Doe",
          "Birth year" => "1991"
        })
      ]

      updated_path = write_tmp_csv(build_csv(updated_rows))
      assert {:ok, second} = CSV.import(FamilyEcho, "Doe Family", updated_path, org)

      assert second.people_created == 0
      assert second.people_updated == 1
      assert Enum.any?(second.people_updated_names, &(&1 =~ "birth_year changed"))

      person = Repo.get_by!(Person, external_id: "family_echo_P1")
      assert person.birth_year == 1991
    end

    test "re-importing same CSV into same family counts as already_in_family", %{org: org} do
      rows = [csv_row(%{"ID" => "P1", "Given names" => "John", "Surname now" => "Doe"})]
      path = write_tmp_csv(build_csv(rows))

      assert {:ok, first} = CSV.import(FamilyEcho, "Doe Family", path, org)
      assert first.people_created == 1
      assert first.people_added_to_family == 0
      assert first.people_already_in_family == 0

      assert {:ok, second} = CSV.import(FamilyEcho, "Doe Family", path, org)
      assert second.people_created == 0
      assert second.people_unchanged == 1
      assert second.people_added_to_family == 0
      assert second.people_already_in_family == 1
    end
  end

  describe "linking existing people across families" do
    test "imports person that exists in another family with identical fields", %{org: org} do
      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Surname now" => "Doe",
          "Birth year" => "1990"
        })
      ]

      path = write_tmp_csv(build_csv(rows))
      family_a = insert(:family, organization: org)
      family_b = insert(:family, organization: org)

      assert {:ok, first} = CSV.import_for_family(FamilyEcho, family_a, path)
      assert first.people_created == 1

      assert {:ok, second} = CSV.import_for_family(FamilyEcho, family_b, path)
      assert second.people_created == 0
      assert second.people_unchanged == 1
      assert second.people_updated == 0
      assert second.people_added_to_family == 1
      assert second.people_already_in_family == 0
      assert second.people_skipped == 0

      person = Repo.get_by!(Person, external_id: "family_echo_P1")
      family_b_people = Ancestry.People.list_people(family_b.id)
      assert Enum.any?(family_b_people, &(&1.id == person.id))
    end

    test "imports person that exists in another family with different fields", %{org: org} do
      first_rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Surname now" => "Doe",
          "Birth year" => "1990"
        })
      ]

      first_path = write_tmp_csv(build_csv(first_rows))
      family_a = insert(:family, organization: org)
      family_b = insert(:family, organization: org)

      assert {:ok, _first} = CSV.import_for_family(FamilyEcho, family_a, first_path)

      updated_rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "John",
          "Surname now" => "Doe",
          "Birth year" => "1991"
        })
      ]

      updated_path = write_tmp_csv(build_csv(updated_rows))
      assert {:ok, second} = CSV.import_for_family(FamilyEcho, family_b, updated_path)

      assert second.people_created == 0
      assert second.people_updated == 1
      assert second.people_added_to_family == 1
      assert second.people_already_in_family == 0
      assert second.people_skipped == 0

      person = Repo.get_by!(Person, external_id: "family_echo_P1")
      assert person.birth_year == 1991
      family_b_people = Ancestry.People.list_people(family_b.id)
      assert Enum.any?(family_b_people, &(&1.id == person.id))
    end
  end

  describe "importing into a fresh organization with previously-used external_ids" do
    test "people from one org are not reused in another org" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      family_a = insert(:family, organization: org_a)
      family_b = insert(:family, organization: org_b)

      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "Adriana",
          "Surname now" => "Smith",
          "Gender" => "Female"
        }),
        csv_row(%{
          "ID" => "P2",
          "Given names" => "Bruno",
          "Surname now" => "Smith",
          "Gender" => "Male"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, summary_a} = CSV.import_for_family(FamilyEcho, family_a, path)
      assert summary_a.people_created == 2

      assert {:ok, summary_b} = CSV.import_for_family(FamilyEcho, family_b, path)
      assert summary_b.people_created == 2
      assert summary_b.people_skipped == 0
      assert summary_b.people_added_to_family == 0
      refute Enum.any?(summary_b.people_errors, &(&1 =~ "organization_mismatch"))

      person_a =
        Repo.get_by!(Person, organization_id: org_a.id, external_id: "family_echo_P1")

      person_b =
        Repo.get_by!(Person, organization_id: org_b.id, external_id: "family_echo_P1")

      assert person_a.id != person_b.id

      {:ok, _updated} =
        People.update_person(person_b, %{given_name: "Adriana B"})

      refreshed_a = Repo.get!(Person, person_a.id)
      assert refreshed_a.given_name == "Adriana"
    end

    test "relationships in one org link only that org's people" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      family_a = insert(:family, organization: org_a)
      family_b = insert(:family, organization: org_b)

      rows = [
        csv_row(%{
          "ID" => "DAD",
          "Given names" => "John",
          "Surname now" => "Smith",
          "Gender" => "Male",
          "Partner ID" => "MOM",
          "Partner name" => "Jane Smith"
        }),
        csv_row(%{
          "ID" => "MOM",
          "Given names" => "Jane",
          "Surname now" => "Smith",
          "Gender" => "Female"
        }),
        csv_row(%{
          "ID" => "KID",
          "Given names" => "Billy",
          "Surname now" => "Smith",
          "Gender" => "Male",
          "Mother ID" => "MOM",
          "Mother name" => "Jane Smith",
          "Father ID" => "DAD",
          "Father name" => "John Smith"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      assert {:ok, _summary_a} = CSV.import_for_family(FamilyEcho, family_a, path)
      assert {:ok, summary_b} = CSV.import_for_family(FamilyEcho, family_b, path)

      assert summary_b.people_created == 3
      assert summary_b.relationships_errors == []

      org_b_person_ids =
        Repo.all(
          from p in Person,
            where: p.organization_id == ^org_b.id,
            select: p.id
        )

      org_b_relationships =
        Repo.all(
          from r in Relationship,
            where: r.person_a_id in ^org_b_person_ids or r.person_b_id in ^org_b_person_ids
        )

      # Every relationship that touches an org_b person should reference
      # only org_b people on BOTH sides — no cross-org leakage.
      for rel <- org_b_relationships do
        assert rel.person_a_id in org_b_person_ids,
               "relationship #{rel.id} (type=#{rel.type}) has person_a from another org"

        assert rel.person_b_id in org_b_person_ids,
               "relationship #{rel.id} (type=#{rel.type}) has person_b from another org"
      end

      # Confirm org_b actually has its own DAD/MOM/KID rows distinct from org_a's.
      dad_a = Repo.get_by!(Person, organization_id: org_a.id, external_id: "family_echo_DAD")
      dad_b = Repo.get_by!(Person, organization_id: org_b.id, external_id: "family_echo_DAD")
      assert dad_a.id != dad_b.id
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
