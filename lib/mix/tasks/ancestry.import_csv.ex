defmodule Mix.Tasks.Ancestry.ImportCsv do
  @moduledoc "Import people and relationships from a CSV file into a new family."
  @shortdoc "Import people from CSV"
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [adapter_name, family_name, csv_path | rest] ->
        adapter =
          try do
            String.to_existing_atom(adapter_name)
          rescue
            ArgumentError -> String.to_atom(adapter_name)
          end

        org =
          case rest do
            [org_id] ->
              Ancestry.Organizations.get_organization!(String.to_integer(org_id))

            [] ->
              case Ancestry.Organizations.list_organizations() do
                [org | _] -> org
                [] -> Mix.raise("No organizations exist. Create one first.")
              end
          end

        case Ancestry.Import.import_from_csv(adapter, family_name, csv_path, org) do
          {:ok, summary} ->
            print_summary(summary)

          {:error, reason} ->
            Mix.shell().error("Error: #{reason}")
        end

      _ ->
        available = Ancestry.Import.available_adapters() |> Enum.join(", ")

        Mix.shell().info("""
        Usage: mix ancestry.import_csv <adapter> <family_name> <csv_path>

        Available adapters: #{available}

        Example:
          mix ancestry.import_csv family_echo "My Family" path/to/export.csv
        """)
    end
  end

  defp print_summary(summary) do
    Mix.shell().info("""
    Import complete!

    Family: #{summary.family.name}

    People created:          #{summary.people_created}
    People updated:          #{summary.people_updated}
    People unchanged:        #{summary.people_unchanged}
    People skipped:          #{summary.people_skipped}
    Relationships created:   #{summary.relationships_created}
    Duplicate relationships: #{summary.relationships_duplicates}
    Relationship errors:     #{length(summary.relationships_errors)}
    """)

    print_list("Unchanged people:", summary.people_unchanged_names, fn name ->
      "#{name} already exists"
    end)

    print_list("Updated people:", summary.people_updated_names, & &1)
    print_list("Skipped people:", summary.people_errors, & &1)
    print_list("Skipped relationships:", summary.relationships_errors, & &1)
  end

  defp print_list(_header, [], _formatter), do: :ok

  defp print_list(header, items, formatter) do
    Mix.shell().info(header)

    Enum.each(items, fn item ->
      Mix.shell().info("  - #{formatter.(item)}")
    end)

    Mix.shell().info("")
  end
end
