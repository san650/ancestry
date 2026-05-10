defmodule Ancestry.Audit.LogTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Audit.Log
  alias Ancestry.Audit.Serializer
  alias Ancestry.Bus.Envelope

  defmodule FakeCommand do
    use Ancestry.Bus.Command

    @enforce_keys [:foo]
    defstruct [:foo]

    @impl true
    def new(_), do: raise("not used")
    @impl true
    def new!(attrs), do: struct!(__MODULE__, attrs)
    @impl true
    def handled_by, do: nil
    @impl true
    def primary_step, do: :foo
    @impl true
    def permission, do: {:test, FakeCommand}
  end

  defp build_envelope do
    account = %{id: 1, name: "Alice", email: "alice@example.com"}
    org = %{id: 9, name: "Acme"}
    scope = %{account: account, organization: org}
    cmd = FakeCommand.new!(%{foo: "bar"})
    Envelope.wrap(scope, cmd)
  end

  test "changeset_from/1 builds a valid changeset from an envelope (org-scoped)" do
    env = build_envelope()

    cs = Log.changeset_from(env)
    assert cs.valid?
    {:ok, row} = Ancestry.Repo.insert(cs)

    assert row.command_id == env.command_id
    assert row.correlation_ids == env.correlation_ids
    assert row.command_module == "Ancestry.Audit.LogTest.FakeCommand"
    assert row.account_id == 1
    assert row.account_name == "Alice"
    assert row.account_email == "alice@example.com"
    assert row.organization_id == 9
    assert row.organization_name == "Acme"
    assert row.payload["arguments"] == %{foo: "bar"}
    assert row.payload["metadata"] == %{}
  end

  test "changeset_from/1 allows nil organization (top-level command)" do
    scope = %{account: %{id: 2, name: nil, email: "bob@x.com"}, organization: nil}
    cmd = FakeCommand.new!(%{foo: "ok"})
    env = Envelope.wrap(scope, cmd)

    cs = Log.changeset_from(env)
    assert cs.valid?
    {:ok, row} = Ancestry.Repo.insert(cs)

    assert is_nil(row.organization_id)
    assert is_nil(row.organization_name)
    assert is_nil(row.account_name)
  end

  test "changeset_from/2 stores handler-supplied metadata under payload.metadata" do
    env = build_envelope()
    cs = Log.changeset_from(env, %{"photo_id" => 7})
    row = Repo.insert!(cs)

    assert row.payload["arguments"] == Serializer.serialize(env.command)
    assert row.payload["metadata"] == %{"photo_id" => 7}
  end

  test "changeset_from/2 rejects empty correlation_ids defensively" do
    env = build_envelope() |> Map.put(:correlation_ids, [])
    cs = Log.changeset_from(env)
    refute cs.valid?
    assert "should have at least 1 item(s)" in errors_on(cs).correlation_ids
  end
end
