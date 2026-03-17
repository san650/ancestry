NimbleCSV.define(Ancestry.Import.CSVParser, separator: ",", escape: "\"")

defmodule Ancestry.Import.CSV do
  @moduledoc """
  Orchestrates CSV import of people and relationships into a new family.

  Uses an adapter module (implementing `Ancestry.Import.CSV.Adapter`) to parse
  rows from a specific CSV format.
  """

  alias Ancestry.Repo
  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships
  alias Ancestry.Import.CSVParser

  @doc """
  Import people and relationships from a CSV file into a new family.

  Returns `{:ok, summary}` on success or `{:error, reason}` on failure.

  The summary map contains:
  - `:family` - the created or found Family struct
  - `:people_created` - count of new people created
  - `:people_updated` - count of existing people updated with changed data
  - `:people_unchanged` - count of existing people with no changes
  - `:people_skipped` - count of rows skipped due to errors
  - `:people_errors` - list of error descriptions
  - `:people_unchanged_names` - list of display names for unchanged people
  - `:people_updated_names` - list of descriptions for updated people
  - `:relationships_created` - count of relationships created
  - `:relationships_duplicates` - count of duplicate relationships skipped
  - `:relationships_errors` - list of error descriptions for real failures
  """
  def import(adapter_module, family_name, csv_path) do
    with :ok <- validate_file(csv_path),
         {:ok, family} <- find_or_create_family(family_name),
         {:ok, rows} <- parse_csv(csv_path) do
      people_result = import_people(adapter_module, family, rows)
      relationships_result = import_relationships(adapter_module, rows)

      {:ok,
       %{
         family: family,
         people_created: people_result.created,
         people_updated: people_result.updated,
         people_unchanged: people_result.unchanged,
         people_skipped: people_result.skipped,
         people_errors: people_result.errors,
         people_unchanged_names: people_result.unchanged_names,
         people_updated_names: people_result.updated_names,
         relationships_created: relationships_result.created,
         relationships_duplicates: relationships_result.duplicates,
         relationships_errors: relationships_result.errors
       }}
    end
  end

  defp find_or_create_family(name) do
    case Repo.get_by(Ancestry.Families.Family, name: name) do
      %Ancestry.Families.Family{} = family -> {:ok, family}
      nil -> Families.create_family(%{name: name})
    end
  end

  defp validate_file(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "File not found: #{path}"}
    end
  end

  defp parse_csv(path) do
    [headers | data_rows] =
      path
      |> File.read!()
      |> CSVParser.parse_string(skip_headers: false)

    headers = Enum.reject(headers, &(&1 == ""))
    header_count = length(headers)

    rows =
      Enum.map(data_rows, fn row ->
        padded = Enum.take(row ++ List.duplicate("", header_count), header_count)
        Enum.zip(headers, padded) |> Map.new()
      end)

    {:ok, rows}
  end

  @import_fields [
    :given_name,
    :surname,
    :given_name_at_birth,
    :surname_at_birth,
    :nickname,
    :title,
    :suffix,
    :gender,
    :living,
    :birth_day,
    :birth_month,
    :birth_year,
    :death_day,
    :death_month,
    :death_year
  ]

  defp import_people(adapter_module, family, rows) do
    initial = %{
      created: 0,
      updated: 0,
      unchanged: 0,
      skipped: 0,
      errors: [],
      unchanged_names: [],
      updated_names: []
    }

    rows
    |> Enum.with_index(2)
    |> Enum.reduce(initial, fn {row, row_num}, acc ->
      case adapter_module.parse_person(row) do
        {:ok, attrs} ->
          import_or_update_person(family, attrs, row_num, acc)

        {:skip, reason} ->
          error = "Row #{row_num}: #{reason}"
          %{acc | skipped: acc.skipped + 1, errors: [error | acc.errors]}
      end
    end)
    |> then(fn result ->
      %{
        result
        | errors: Enum.reverse(result.errors),
          unchanged_names: Enum.reverse(result.unchanged_names),
          updated_names: Enum.reverse(result.updated_names)
      }
    end)
  end

  defp import_or_update_person(family, attrs, row_num, acc) do
    case Repo.get_by(Person, external_id: attrs.external_id) do
      nil ->
        case People.create_person(family, attrs) do
          {:ok, _person} ->
            %{acc | created: acc.created + 1}

          {:error, changeset} ->
            error = "Row #{row_num}: #{inspect(format_errors(changeset))}"
            %{acc | skipped: acc.skipped + 1, errors: [error | acc.errors]}
        end

      %Person{} = existing ->
        name = Person.display_name(existing)
        changed_fields = detect_changes(existing, attrs)

        if changed_fields == [] do
          %{acc | unchanged: acc.unchanged + 1, unchanged_names: [name | acc.unchanged_names]}
        else
          case People.update_person(existing, attrs) do
            {:ok, _person} ->
              desc = "#{name}: #{Enum.join(changed_fields, ", ")} changed"
              %{acc | updated: acc.updated + 1, updated_names: [desc | acc.updated_names]}

            {:error, changeset} ->
              error =
                "Row #{row_num}: update failed for #{name}: #{inspect(format_errors(changeset))}"

              %{acc | skipped: acc.skipped + 1, errors: [error | acc.errors]}
          end
        end
    end
  end

  defp detect_changes(%Person{} = existing, attrs) do
    Enum.filter(@import_fields, fn field ->
      old_value = Map.get(existing, field)
      new_value = Map.get(attrs, field)
      new_value != nil and new_value != old_value
    end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp import_relationships(adapter_module, rows) do
    rows
    |> Enum.flat_map(&adapter_module.parse_relationships/1)
    |> Enum.reduce(%{created: 0, duplicates: 0, errors: []}, fn {type, source_eid, target_eid,
                                                                 metadata},
                                                                acc ->
      source = Repo.get_by(Person, external_id: source_eid)
      target = Repo.get_by(Person, external_id: target_eid)

      cond do
        is_nil(source) ->
          error = "#{type}: person \"#{source_eid}\" not found"
          %{acc | errors: [error | acc.errors]}

        is_nil(target) ->
          error = "#{type}: person \"#{target_eid}\" not found"
          %{acc | errors: [error | acc.errors]}

        true ->
          case Relationships.create_relationship(source, target, Atom.to_string(type), metadata) do
            {:ok, _rel} ->
              %{acc | created: acc.created + 1}

            {:error, :max_parents_reached} ->
              error = "#{type}: max 2 parents for \"#{target_eid}\""
              %{acc | errors: [error | acc.errors]}

            {:error, %Ecto.Changeset{} = changeset} ->
              if duplicate_relationship?(changeset) do
                %{acc | duplicates: acc.duplicates + 1}
              else
                error =
                  "#{type} #{source_eid} -> #{target_eid}: #{inspect(format_errors(changeset))}"

                %{acc | errors: [error | acc.errors]}
              end
          end
      end
    end)
    |> then(fn result -> %{result | errors: Enum.reverse(result.errors)} end)
  end

  defp duplicate_relationship?(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Keyword.get_values(:person_a_id)
    |> Enum.any?(fn {msg, _} -> msg =~ "already exists" end)
  end
end
