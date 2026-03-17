defmodule Ancestry.Import do
  @moduledoc """
  Entry point for importing data from external sources.

  Dispatches to the appropriate adapter based on the adapter name.
  """

  alias Ancestry.Import.CSV

  @adapters %{
    family_echo: Ancestry.Import.CSV.FamilyEcho
  }

  @doc """
  Import people and relationships from a CSV file into a new family.

  ## Parameters

  - `adapter_name` - atom identifying the CSV format (e.g. `:family_echo`)
  - `family_name` - name for the new family to create
  - `csv_path` - path to the CSV file

  ## Returns

  - `{:ok, summary}` on success with counts of created/skipped/errored records
  - `{:error, reason}` on failure
  """
  def import_from_csv(adapter_name, family_name, csv_path) do
    case Map.fetch(@adapters, adapter_name) do
      {:ok, adapter_module} ->
        CSV.import(adapter_module, family_name, csv_path)

      :error ->
        available = @adapters |> Map.keys() |> Enum.join(", ")
        {:error, "Unknown adapter: #{adapter_name}. Available: #{available}"}
    end
  end

  @doc """
  Returns the list of available adapter names.
  """
  def available_adapters, do: Map.keys(@adapters)
end
