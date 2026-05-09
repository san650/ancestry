defmodule Ancestry.Audit.Serializer do
  @moduledoc """
  Serializes a command struct to a map suitable for jsonb storage.
  Replaces redacted fields with "[redacted]" and binary blobs with
  "binary-blob".
  """

  def serialize(%module{} = cmd) do
    redacted = MapSet.new(module.redacted_fields())
    binaries = MapSet.new(module.binary_fields())

    cmd
    |> Map.from_struct()
    |> Map.new(fn {k, v} ->
      cond do
        k in redacted -> {k, "[redacted]"}
        k in binaries -> {k, "binary-blob"}
        true -> {k, v}
      end
    end)
  end
end
