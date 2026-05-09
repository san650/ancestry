defmodule Ancestry.Bus.Envelope do
  @moduledoc """
  Wraps an inbound command with the dispatcher metadata required for
  authorization, audit, and tracing: caller scope, command/correlation
  ids, and issuance timestamp.
  """

  alias Ancestry.Prefixes
  require Logger

  @enforce_keys [:scope, :command_id, :correlation_id, :issued_at, :command]
  defstruct [:scope, :command_id, :correlation_id, :issued_at, :command]

  @type t :: %__MODULE__{
          scope: Ancestry.Identity.Scope.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          issued_at: DateTime.t(),
          command: struct()
        }

  @spec wrap(term(), struct(), keyword()) :: t()
  def wrap(scope, command, opts \\ []) do
    %__MODULE__{
      scope: scope,
      command: command,
      command_id: Prefixes.generate(:command),
      correlation_id:
        opts[:correlation_id] || current_request_id() || Prefixes.generate(:request),
      issued_at: DateTime.utc_now()
    }
  end

  defp current_request_id, do: Logger.metadata()[:request_id]
end
