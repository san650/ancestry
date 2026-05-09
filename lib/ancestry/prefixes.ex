defmodule Ancestry.Prefixes do
  @moduledoc """
  Single source of truth for prefixes used in external/exposed ids
  throughout the application. Format: `<prefix>-<uuid>`.

  Add an entry whenever introducing a new prefixed id. Compile-time
  checks enforce uniqueness and length (3–4 chars).
  """

  @prefixes %{
    command: "cmd",
    request: "req",
    account: "acc",
    organization: "org",
    photo: "pho",
    gallery: "gal",
    family: "fam",
    person: "per",
    comment: "com",
    batch: "bch"
  }

  values = Map.values(@prefixes)

  case values -- Enum.uniq(values) do
    [] -> :ok
    dup -> raise "duplicate id prefixes: #{inspect(dup)}"
  end

  for v <- values,
      byte_size(v) not in 3..4,
      do: raise("id prefix must be 3 or 4 chars: #{inspect(v)}")

  @spec for!(atom()) :: String.t()
  def for!(kind) when is_map_key(@prefixes, kind), do: Map.fetch!(@prefixes, kind)

  @spec generate(atom()) :: String.t()
  def generate(kind), do: for!(kind) <> "-" <> Ecto.UUID.generate()

  @spec parse!(String.t()) :: {String.t(), String.t()}
  def parse!(id) when is_binary(id) do
    [prefix, rest] = String.split(id, "-", parts: 2)

    if prefix in Map.values(@prefixes),
      do: {prefix, rest},
      else: raise(ArgumentError, "unknown id prefix: #{inspect(prefix)} in #{inspect(id)}")
  end

  @spec known_kinds() :: [atom()]
  def known_kinds, do: Map.keys(@prefixes)
end
