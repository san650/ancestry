defmodule Ancestry.Bus.Handler do
  @moduledoc """
  Behaviour for command handlers. A handler returns the `Ecto.Multi`
  describing the persistence work for a command. The `Ancestry.Bus`
  dispatcher prepends the audit row insertion, runs the transaction,
  and fires post-commit effects.
  """

  @callback build_multi(Ancestry.Bus.Envelope.t()) :: Ecto.Multi.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Handler
      alias Ecto.Multi
    end
  end
end
