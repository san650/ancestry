defmodule Web.AuditLogLive.Shared do
  @moduledoc "Helpers shared between AuditLogLive.Index and AuditLogLive.OrgIndex."

  def parse_int(nil), do: nil
  def parse_int(""), do: nil
  def parse_int(s) when is_binary(s), do: String.to_integer(s)

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, val), do: Map.put(map, key, val)

  def cursor_from([]), do: nil
  def cursor_from(rows), do: rows |> List.last() |> then(&{&1.inserted_at, &1.id})

  def matches_filters?(row, filters) do
    Enum.all?(filters, fn
      {:organization_id, id} -> row.organization_id == id
      {:account_id, id} -> row.account_id == id
      {:correlation_id, id} -> id in row.correlation_ids
      {:before, _} -> true
    end)
  end
end
