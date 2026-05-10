defmodule Ancestry.Bus.Step do
  @moduledoc """
  DSL for assembling handler transactions. Centralizes the reserved
  `:envelope`, `:audit`, and `:effects` steps; thin pass-throughs for
  the rest of `Ecto.Multi` and Oban.
  """

  alias Ancestry.Audit.Log
  alias Ancestry.Authorization
  alias Ecto.Multi

  @doc "Start a new transaction Multi seeded with the envelope."
  def new(envelope) do
    Multi.new() |> Multi.put(:envelope, envelope)
  end

  defdelegate put(multi, name, value), to: Multi

  @doc """
  Append an insert step. The function receives the Multi changes map and must
  return either an `Ecto.Changeset` or a `{changeset, opts}` tuple. When a
  tuple is returned the opts are forwarded to `Repo.insert/2` (e.g. for
  `on_conflict` upserts).
  """
  def insert(multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, &run_insert(&1, &2, fun))
  end

  defdelegate update(multi, name, changeset_or_fun), to: Multi
  defdelegate delete(multi, name, struct_or_fun), to: Multi
  defdelegate run(multi, name, fun), to: Multi
  defdelegate delete_all(multi, name, queryable), to: Multi

  @doc "Atomically enqueue an Oban job alongside the rest of the transaction."
  defdelegate enqueue(multi, name, fun), to: Oban, as: :insert

  @doc """
  Append a load+authorize step. Reads the id from `envelope.command.<id_field>`,
  loads `queryable` by primary key, then calls `Authorization.can?(scope, action, record)`.

  Returns the loaded record or `{:error, :not_found}` / `{:error, :unauthorized}`.
  """
  def authorize(multi, name, queryable, action, id_field)
      when is_atom(action) and is_atom(id_field) do
    Multi.run(multi, name, &run_authorize(&1, &2, queryable, action, id_field))
  end

  @doc "Append the audit step (writes one row to audit_log on commit)."
  def audit(multi), do: Multi.insert(multi, :audit, &create_audit_log/1)

  @doc """
  Append the audit step with handler-contributed metadata. `fun` receives the
  Multi changes map and returns a metadata map written to `payload.metadata`.
  """
  def audit(multi, fun) when is_function(fun, 1) do
    multi
    |> Multi.run(:audit_metadata, &run_metadata_fun(&1, &2, fun))
    |> Multi.insert(:audit, &create_audit_log_with_metadata/1)
  end

  @doc "Append an effects step that returns the post-commit effect list."
  def effects(multi, fun), do: Multi.run(multi, :effects, fun)

  @doc "Append a no-op effects step. Convenience for handlers with nothing to fire."
  def no_effects(multi), do: effects(multi, &empty_effects/2)

  defp create_audit_log(%{envelope: envelope}), do: Log.changeset_from(envelope)

  defp create_audit_log_with_metadata(%{envelope: env, audit_metadata: meta}),
    do: Log.changeset_from(env, meta)

  defp run_metadata_fun(_repo, changes, fun), do: {:ok, stringify_keys(fun.(changes))}

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp empty_effects(_repo, _changes), do: {:ok, []}

  defp run_insert(repo, changes, fun) do
    case fun.(changes) do
      {%Ecto.Changeset{} = changeset, opts} -> repo.insert(changeset, opts)
      %Ecto.Changeset{} = changeset -> repo.insert(changeset)
    end
  end

  defp run_authorize(repo, %{envelope: env}, queryable, action, id_field) do
    id = Map.fetch!(env.command, id_field)

    case repo.get(queryable, id) do
      nil ->
        {:error, :not_found}

      record ->
        if Authorization.can?(env.scope, action, record),
          do: {:ok, record},
          else: {:error, :unauthorized}
    end
  end
end
