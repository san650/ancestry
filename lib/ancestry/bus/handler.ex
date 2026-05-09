defmodule Ancestry.Bus.Handler do
  @moduledoc """
  Behaviour for command handlers. A handler exposes `handle/1` which
  runs the transaction and returns the result map (on success) or an
  Ecto.Multi error tuple (on failure).
  """

  @callback handle(Ancestry.Bus.Envelope.t()) ::
              {:ok, map()}
              | {:error, atom() | term(), term(), map()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Handler
    end
  end
end
