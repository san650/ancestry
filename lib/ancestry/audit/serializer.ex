defmodule Ancestry.Audit.Serializer do
  @moduledoc """
  Serializes a command struct into the audit-row payload. Replaced by
  the full implementation (with redaction, binary handling, etc.) in
  the next task.
  """

  def serialize(%_{} = cmd) do
    Map.from_struct(cmd)
  end
end
