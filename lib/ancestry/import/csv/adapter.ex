defmodule Ancestry.Import.CSV.Adapter do
  @moduledoc """
  Behaviour for CSV import adapters.

  Each adapter knows how to parse rows from a specific CSV format
  into person attributes and relationship tuples.
  """

  @doc """
  Parse a CSV row map into person attributes.

  Returns `{:ok, attrs_map}` on success, or `{:skip, reason}` if the row
  should be skipped (e.g. missing required fields).
  """
  @callback parse_person(row :: map()) :: {:ok, map()} | {:skip, String.t()}

  @doc """
  Parse a CSV row map into a list of relationship tuples.

  Each tuple is `{type, source_external_id, target_external_id, metadata}` where:
  - `type` is an atom like `:parent`, `:married`, `:relationship`, `:divorced`, `:separated`
  - `source_external_id` and `target_external_id` are prefixed external IDs
  - `metadata` is a map of additional relationship attributes
  """
  @callback parse_relationships(row :: map()) :: [{atom(), String.t(), String.t(), map()}]
end
