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
    assert [<<"req-", _::binary-size(36)>>] = env.correlation_ids
    assert %DateTime{} = env.issued_at
  end

  test "wrap/3 honors :correlation_ids from opts" do
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_ids: ["bch-fixed"])
    assert env.correlation_ids == ["bch-fixed"]
  end

  test "wrap/3 falls back to Logger.metadata[:request_id] when present" do
    Logger.metadata(request_id: "req-from-logger")
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{})
    assert env.correlation_ids == ["req-from-logger"]
  end

  test "wrap/3 prepends supplied correlation_ids before the request id" do
    Logger.metadata(request_id: "req-abc")
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_ids: ["bch-x"])
    assert env.correlation_ids == ["bch-x", "req-abc"]
  after
    Logger.metadata(request_id: nil)
  end

  test "wrap/3 dedupes when supplied id matches the request id" do
    Logger.metadata(request_id: "req-abc")
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{}, correlation_ids: ["req-abc"])
    assert env.correlation_ids == ["req-abc"]
  after
    Logger.metadata(request_id: nil)
  end

  test "wrap/3 falls back to a generated req- id when nothing is supplied" do
    env = Envelope.wrap(%{account: %{id: 1}}, %FakeCommand{})
    assert [<<"req-", _::binary-size(36)>>] = env.correlation_ids
  end
end
