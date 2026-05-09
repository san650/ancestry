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

  defmodule NotFoundHandler do
    use Ancestry.Bus.Handler

    @impl true
    def build_multi(_env) do
      Multi.new()
      |> Multi.run(:boom, fn _, _ -> {:error, :not_found} end)
    end
  end

  defmodule ChangesetHandler do
    use Ancestry.Bus.Handler

    @impl true
    def build_multi(_env) do
      Multi.new()
      |> Multi.run(:cs, fn _, _ ->
        cs = %Ecto.Changeset{data: %{}, types: %{}, valid?: false, action: :validate}
        {:error, Ecto.Changeset.add_error(cs, :base, "bad")}
      end)
    end
  end

  defmodule UnauthorizedStepHandler do
    use Ancestry.Bus.Handler

    @impl true
    def build_multi(_env) do
      Multi.new()
      |> Multi.run(:authz, fn _, _ -> {:error, :unauthorized} end)
    end
  end

  defmodule HandlerErrorHandler do
    use Ancestry.Bus.Handler

    @impl true
    def build_multi(_env) do
      Multi.new()
      |> Multi.run(:weird, fn _, _ -> {:error, :something_else} end)
    end
  end

  for {mod_name, handler} <- [
        {NotFoundCommand, NotFoundHandler},
        {ChangesetCommand, ChangesetHandler},
        {UnauthorizedCommand, UnauthorizedStepHandler},
        {HandlerErrorCommand, HandlerErrorHandler}
      ] do
    defmodule mod_name do
      use Ancestry.Bus.Command
      defstruct []
      @impl true
      def new(_), do: {:ok, %__MODULE__{}}
      @impl true
      def new!(_), do: %__MODULE__{}
      @impl true
      def handled_by, do: unquote(handler)
      @impl true
      def primary_step, do: :result
      @impl true
      def permission, do: {:read, Ancestry.Identity.Account}
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

  test "classifies :not_found from a Multi step", %{scope: scope} do
    assert {:error, :not_found} = Bus.dispatch(scope, NotFoundCommand.new!(%{}))
    assert Ancestry.Repo.all(Log) == []
  end

  test "classifies a changeset failure as :validation", %{scope: scope} do
    assert {:error, :validation, %Ecto.Changeset{}} =
             Bus.dispatch(scope, ChangesetCommand.new!(%{}))
  end

  test "classifies :unauthorized from a Multi step", %{scope: scope} do
    assert {:error, :unauthorized} = Bus.dispatch(scope, UnauthorizedCommand.new!(%{}))
  end

  test "classifies unrecognized handler errors as :handler", %{scope: scope} do
    assert {:error, :handler, :something_else} =
             Bus.dispatch(scope, HandlerErrorCommand.new!(%{}))
  end

  defmodule DeniedCommand do
    use Ancestry.Bus.Command
    defstruct []

    @impl true
    def new(_), do: {:ok, %__MODULE__{}}
    @impl true
    def new!(_), do: %__MODULE__{}
    @impl true
    def handled_by, do: Ancestry.BusTest.NoopHandler
    @impl true
    def primary_step, do: :result
    @impl true
    def permission, do: {:delete, Ancestry.Organizations.Organization}
  end

  test "returns {:error, :unauthorized} when Permit denies" do
    {:ok, viewer} =
      %Ancestry.Identity.Account{
        email: "viewer-bus-test@example.com",
        name: "Viewer",
        role: :viewer,
        hashed_password: Bcrypt.hash_pwd_salt("password")
      }
      |> Ancestry.Repo.insert()

    viewer_scope = %Ancestry.Identity.Scope{account: viewer, organization: nil}
    cmd = DeniedCommand.new!(%{})
    assert {:error, :unauthorized} = Bus.dispatch(viewer_scope, cmd)
    assert Ancestry.Repo.all(Log) == []
  end
end
