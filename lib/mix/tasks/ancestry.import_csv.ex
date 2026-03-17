defmodule Mix.Tasks.Ancestry.ImportCsv do
  @moduledoc "Import people and relationships from a CSV file into a new family."
  @shortdoc "Import people from CSV"
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [adapter_name, family_name, csv_path] ->
        adapter =
          try do
            String.to_existing_atom(adapter_name)
          rescue
            ArgumentError -> String.to_atom(adapter_name)
          end

        case Ancestry.Import.import_from_csv(adapter, family_name, csv_path) do
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

    People created:         #{summary.people_created}
    People skipped:         #{summary.people_skipped}
    Relationships created:  #{summary.relationships_created}
    Duplicate relationships: #{summary.relationships_duplicates}
    Relationship errors:    #{length(summary.relationships_errors)}
    """)

    if summary.people_errors != [] do
      Mix.shell().info("Skipped people:")

      Enum.each(summary.people_errors, fn error ->
        Mix.shell().info("  - #{error}")
      end)

      Mix.shell().info("")
    end

    if summary.relationships_errors != [] do
      Mix.shell().info("Skipped relationships:")

      Enum.each(summary.relationships_errors, fn error ->
        Mix.shell().info("  - #{error}")
      end)

      Mix.shell().info("")
    end
  end
end
