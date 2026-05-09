defmodule Ancestry.Bus.Command do
  @moduledoc """
  Behaviour for command structs dispatched through `Ancestry.Bus`.

  A command is plain data: a struct of fields that describe an intent.
  Each command points at a single handler module and declares the
  Permit permission required to dispatch it. Optional callbacks
  describe how the command should be serialized into an audit row.
  """

  @callback new(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback new!(map() | keyword()) :: struct()
  @callback handled_by() :: module()
  @callback primary_step() :: atom()
  @callback permission() :: {atom(), module()}
  @callback redacted_fields() :: [atom()]
  @callback binary_fields() :: [atom()]

  @optional_callbacks redacted_fields: 0, binary_fields: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Ancestry.Bus.Command
      def redacted_fields, do: []
      def binary_fields, do: []
      defoverridable redacted_fields: 0, binary_fields: 0
    end
  end
end
