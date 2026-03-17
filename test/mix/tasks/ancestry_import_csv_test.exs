defmodule Mix.Tasks.Ancestry.ImportCsvTest do
  use Ancestry.DataCase, async: false

  import ExUnit.CaptureIO

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

  describe "run/1" do
    test "happy path: imports CSV and prints summary" do
      rows = [
        csv_row(%{
          "ID" => "P1",
          "Given names" => "Alice",
          "Surname now" => "Smith",
          "Gender" => "Female",
          "Partner ID" => "P2",
          "Partner name" => "Bob Smith"
        }),
        csv_row(%{
          "ID" => "P2",
          "Given names" => "Bob",
          "Surname now" => "Smith",
          "Gender" => "Male"
        })
      ]

      path = write_tmp_csv(build_csv(rows))

      output =
        capture_io(fn ->
          Mix.Tasks.Ancestry.ImportCsv.run(["family_echo", "Smith Family", path])
        end)

      assert output =~ "Import complete"
      assert output =~ "Smith Family"
      assert output =~ "People created: 2"
      assert output =~ "Relationships created: 1"
    end

    test "prints usage on wrong number of args" do
      output =
        capture_io(fn ->
          Mix.Tasks.Ancestry.ImportCsv.run([])
        end)

      assert output =~ "Usage:"
    end

    test "prints error for unknown adapter" do
      output =
        capture_io(fn ->
          Mix.Tasks.Ancestry.ImportCsv.run(["nonexistent", "Family", "file.csv"])
        end)

      assert output =~ "Error:"
      assert output =~ "Unknown adapter"
    end

    test "prints error when file not found" do
      output =
        capture_io(fn ->
          Mix.Tasks.Ancestry.ImportCsv.run(["family_echo", "Family", "/no/such/file.csv"])
        end)

      assert output =~ "Error:"
      assert output =~ "File not found"
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
    path =
      Path.join(System.tmp_dir!(), "test_mix_import_#{System.unique_integer([:positive])}.csv")

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
