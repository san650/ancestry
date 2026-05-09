defmodule Ancestry.Bus.Step do
  @moduledoc """
  DSL for assembling handler transactions. Centralizes the reserved
  `:envelope`, `:audit`, and `:effects` steps; thin pass-throughs for
  the rest of `Ecto.Multi` and Oban.
  """

  alias Ancestry.Audit.Log
  alias Ecto.Multi

  @doc "Start a new transaction Multi seeded with the envelope."
  def new(envelope) do
    Multi.new() |> Multi.put(:envelope, envelope)
  end

  defdelegate put(multi, name, value), to: Multi
  defdelegate insert(multi, name, changeset_or_fun), to: Multi
  defdelegate insert(multi, name, changeset_or_fun, opts), to: Multi
  defdelegate update(multi, name, changeset_or_fun), to: Multi
  defdelegate delete(multi, name, struct_or_fun), to: Multi
  defdelegate run(multi, name, fun), to: Multi
  defdelegate delete_all(multi, name, queryable), to: Multi

  @doc "Atomically enqueue an Oban job alongside the rest of the transaction."
  defdelegate enqueue(multi, name, fun), to: Oban, as: :insert

  @doc "Append the audit step (writes one row to audit_log on commit)."
  def audit(multi), do: Multi.insert(multi, :audit, &create_audit_log/1)

  @doc "Append an effects step that returns the post-commit effect list."
  def effects(multi, fun), do: Multi.run(multi, :effects, fun)

  @doc "Append a no-op effects step. Convenience for handlers with nothing to fire."
  def no_effects(multi), do: effects(multi, &empty_effects/2)

  defp create_audit_log(%{envelope: envelope}), do: Log.changeset_from(envelope)
  defp empty_effects(_repo, _changes), do: {:ok, []}
end
