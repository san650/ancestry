defmodule Ancestry.Bus.Envelope do
  @moduledoc """
  Wraps an inbound command with the dispatcher metadata required for
  authorization, audit, and tracing: caller scope, command/correlation
  ids, and issuance timestamp.
  """

  alias Ancestry.Prefixes
  require Logger

  @enforce_keys [:scope, :command_id, :correlation_ids, :issued_at, :command]
  defstruct [:scope, :command_id, :correlation_ids, :issued_at, :command]

  @type t :: %__MODULE__{
          scope: Ancestry.Identity.Scope.t(),
          command_id: String.t(),
          correlation_ids: [String.t()],
          issued_at: DateTime.t(),
          command: struct()
        }

  @spec wrap(term(), struct(), keyword()) :: t()
  def wrap(scope, command, opts \\ []) do
    ids =
      (List.wrap(opts[:correlation_ids]) ++ [current_request_id()])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> ensure_at_least_one()

    %__MODULE__{
      scope: scope,
      command: command,
      command_id: Prefixes.generate(:command),
      correlation_ids: ids,
      issued_at: DateTime.utc_now()
    }
  end

  defp ensure_at_least_one([]), do: [Prefixes.generate(:request)]
  defp ensure_at_least_one(list), do: list

  defp current_request_id, do: Logger.metadata()[:request_id]
end
