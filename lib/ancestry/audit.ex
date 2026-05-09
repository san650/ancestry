defmodule Ancestry.Audit do
  @moduledoc """
  Read-only queries over the `audit_log` table. Mutations flow through
  `Ancestry.Bus` exclusively.
  """

  import Ecto.Query

  alias Ancestry.Audit.Log
  alias Ancestry.Repo

  @default_limit 50

  @doc """
  Lists audit-log entries newest first. Filters: `:organization_id`, `:account_id`,
  `:before` (a `{NaiveDateTime, id}` cursor — only rows strictly older are returned).
  """
  def list_entries(filters, limit \\ @default_limit) when is_map(filters) do
    Log
    |> apply_filter(:organization_id, filters)
    |> apply_filter(:account_id, filters)
    |> apply_cursor(filters)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp apply_filter(query, :organization_id, %{organization_id: id}) when not is_nil(id),
    do: where(query, [l], l.organization_id == ^id)

  defp apply_filter(query, :account_id, %{account_id: id}) when not is_nil(id),
    do: where(query, [l], l.account_id == ^id)

  defp apply_filter(query, _key, _filters), do: query

  defp apply_cursor(query, %{before: {ts, id}}) when not is_nil(ts) and not is_nil(id) do
    where(query, [l], {l.inserted_at, l.id} < {^ts, ^id})
  end

  defp apply_cursor(query, _filters), do: query

  @doc "Every row sharing `correlation_id`, oldest first."
  def list_correlated_entries(correlation_id) when is_binary(correlation_id) do
    Log
    |> where([l], l.correlation_id == ^correlation_id)
    |> order_by([l], asc: l.inserted_at, asc: l.id)
    |> Repo.all()
  end

  @doc """
  Distinct `%{id, email}` of accounts that have appeared in the audit log.
  Optionally scoped to an organization via `:organization_id`.
  """
  def list_audit_accounts(filters) when is_map(filters) do
    Log
    |> apply_filter(:organization_id, filters)
    |> select([l], %{id: l.account_id, email: l.account_email})
    |> distinct(true)
    |> order_by([l], asc: l.account_email)
    |> Repo.all()
  end
end
