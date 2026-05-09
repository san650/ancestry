defmodule Ancestry.Audit.Log do
  @moduledoc """
  Denormalized OLAP-style audit row written by `Ancestry.Bus` for every
  successful command dispatch. Failures and request stream metadata are
  recorded via telemetry/Logger instead.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ancestry.Audit.Serializer

  schema "audit_log" do
    field :command_id, :string
    field :correlation_ids, {:array, :string}, default: []
    field :command_module, :string
    field :account_id, :integer
    field :account_name, :string
    field :account_email, :string
    field :organization_id, :integer
    field :organization_name, :string
    field :payload, :map

    timestamps(updated_at: false)
  end

  @required ~w(command_id correlation_ids command_module account_id account_email payload)a
  @optional ~w(account_name organization_id organization_name)a

  def changeset_from(env, metadata \\ %{}) do
    %__MODULE__{}
    |> cast(attrs_from(env, metadata), @required ++ @optional)
    |> force_change(:correlation_ids, env.correlation_ids)
    |> validate_required(@required)
    |> validate_length(:correlation_ids, min: 1)
  end

  defp attrs_from(env, metadata) do
    %{
      command_id: env.command_id,
      correlation_ids: env.correlation_ids,
      command_module: inspect(env.command.__struct__),
      account_id: env.scope.account.id,
      account_name: env.scope.account.name,
      account_email: env.scope.account.email,
      organization_id: org_id(env.scope),
      organization_name: org_name(env.scope),
      payload: %{
        "arguments" => Serializer.serialize(env.command),
        "metadata" => metadata
      }
    }
  end

  defp org_id(%{organization: %{id: id}}), do: id
  defp org_id(_), do: nil
  defp org_name(%{organization: %{name: n}}), do: n
  defp org_name(_), do: nil
end
