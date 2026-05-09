defmodule Ancestry.BusTest do
  use Ancestry.DataCase, async: false

  alias Ancestry.Bus
  alias Ancestry.Audit.Log
  alias Ecto.Multi

  defmodule NoopCommand do
    use Ancestry.Bus.Command
    @enforce_keys [:label]
    defstruct [:label]

    @impl true
    def new(attrs) do
      cs =
        {%{}, %{label: :string}}
        |> Ecto.Changeset.cast(attrs, [:label])
        |> Ecto.Changeset.validate_required([:label])

      if cs.valid?,
        do: {:ok, struct!(__MODULE__, Ecto.Changeset.apply_changes(cs))},
        else: {:error, %{cs | action: :validate}}
    end

    @impl true
    def new!(attrs), do: struct!(__MODULE__, attrs)
    @impl true
    def handled_by, do: Ancestry.BusTest.NoopHandler
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:read, Ancestry.Identity.Account}
  end

  defmodule NoopHandler do
    use Ancestry.Bus.Handler

    @impl true
    def build_multi(%Ancestry.Bus.Envelope{command: cmd}) do
      Multi.new()
      |> Multi.put(:result, %{label: cmd.label, ok: true})
      |> Multi.run(:__effects__, fn _, _ -> {:ok, []} end)
    end
  end

  setup do
    {:ok, account} =
      %Ancestry.Identity.Account{
        email: "admin-bus-test@example.com",
        name: "Admin",
        role: :admin,
        hashed_password: Bcrypt.hash_pwd_salt("password")
      }
      |> Ancestry.Repo.insert()

    scope = %Ancestry.Identity.Scope{account: account, organization: nil}
    {:ok, scope: scope}
  end

  test "dispatch/2 returns the primary step result and writes an audit row", %{scope: scope} do
    {:ok, cmd} = NoopCommand.new(%{label: "hello"})

    assert {:ok, %{label: "hello", ok: true}} = Bus.dispatch(scope, cmd)

    assert [row] = Ancestry.Repo.all(Log)
    assert <<"cmd-", _::binary-size(36)>> = row.command_id
    assert row.command_module == "Ancestry.BusTest.NoopCommand"
    assert row.account_id == scope.account.id
    assert row.payload == %{"label" => "hello"}
  end
end
