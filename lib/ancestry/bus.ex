defmodule Ancestry.Bus do
  @moduledoc """
  Single dispatcher for state-mutating commands. Wraps every dispatch
  with authorization, audit-row insertion, and post-commit effects.
  """

  alias Ancestry.Authorization
  alias Ancestry.Bus.Envelope
  require Logger

  def dispatch(scope, command, opts \\ []),
    do: dispatch_envelope(Envelope.wrap(scope, command, opts))

  def dispatch_envelope(%Envelope{command: %module{}} = env) do
    Logger.metadata(
      command_id: env.command_id,
      correlation_id: env.correlation_id,
      command_module: inspect(module)
    )

    :telemetry.span(
      [:ancestry, :bus, :dispatch],
      base_metadata(env),
      fn ->
        result = do_dispatch(env, module)
        {result, Map.merge(base_metadata(env), outcome_metadata(result))}
      end
    )
  end

  defp do_dispatch(env, module) do
    {action, resource} = module.permission()

    if Authorization.can?(env.scope, action, resource) do
      run(env, module)
    else
      Logger.warning("authz_denied",
        command_id: env.command_id,
        command_module: inspect(module),
        action: action,
        resource: inspect(resource)
      )

      {:error, :unauthorized}
    end
  end

  defp run(env, module) do
    case module.handled_by().handle(env) do
      {:ok, changes} ->
        Enum.each(changes[:effects] || [], &run_effect/1)
        {:ok, Map.fetch!(changes, module.primary_step())}

      {:error, _step, %Ecto.Changeset{} = cs, _changes} ->
        {:error, :validation, cs}

      {:error, _step, :not_found, _} ->
        {:error, :not_found}

      {:error, _step, {:not_found, _}, _} ->
        {:error, :not_found}

      {:error, _step, :unauthorized, _} ->
        {:error, :unauthorized}

      {:error, _step, {:conflict, t}, _} ->
        {:error, :conflict, t}

      {:error, _step, other, _} ->
        {:error, :handler, other}
    end
  end

  defp run_effect({:broadcast, topic, msg}),
    do: Phoenix.PubSub.broadcast(Ancestry.PubSub, topic, msg)

  defp base_metadata(env) do
    %{
      command_id: env.command_id,
      correlation_id: env.correlation_id,
      command_module: inspect(env.command.__struct__),
      account_id: env.scope.account.id,
      organization_id: scope_org_id(env.scope)
    }
  end

  defp outcome_metadata({:ok, _}), do: %{outcome: :ok, error_tag: nil}
  defp outcome_metadata({:error, tag}), do: %{outcome: :error, error_tag: tag}
  defp outcome_metadata({:error, tag, _}), do: %{outcome: :error, error_tag: tag}

  defp scope_org_id(%{organization: %{id: id}}), do: id
  defp scope_org_id(_), do: nil
end
