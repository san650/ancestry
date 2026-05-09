defmodule Ancestry.Bus.EnvelopeTest do
  use ExUnit.Case, async: false

  alias Ancestry.Bus.Envelope

  defmodule FakeCommand do
    defstruct [:foo]
  end

  setup do
    Logger.metadata([])
    :ok
  end

  test "wrap/2 builds an envelope with prefixed ids and current timestamp" do
    scope = %{account: %{id: 1}, organization: nil}
    command = %FakeCommand{foo: :bar}

    env = Envelope.wrap(scope, command)

    assert env.scope == scope
    assert env.command == command
    assert <<"cmd-", _::binary-size(36)>> = env.command_id
    assert <<"req-", _::binary-size(36)>> = env.correlation_id
    assert %DateTime{} = env.issued_at
  end

  test "wrap/3 honors :correlation_id from opts" do
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_id: "req-fixed")
    assert env.correlation_id == "req-fixed"
  end

  test "wrap/3 falls back to Logger.metadata[:request_id] when present" do
    Logger.metadata(request_id: "req-from-logger")
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{})
    assert env.correlation_id == "req-from-logger"
  end
end
